package dumper

import (
	"archive/tar"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strconv"
	"strings"

	log "github.com/sirupsen/logrus"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/tools/portforward"
	"k8s.io/client-go/tools/remotecommand"
	"k8s.io/client-go/transport/spdy"
)

var (
	// Ignore this error only in case when all calls to portForwardPod have the same context.
	// If it is not the case, igoning this error may result in a portForward closing while other
	// entities is in process of using it.
	ERR_PORT_ALREADY_FORWARDED = errors.New("this localPort:remotePort is already forwarded")
	ERR_LOCAL_PORT_IN_USE      = errors.New("this localPort is already in use")
)

/*
Forwards ports to a specific pod. Close the returned channel to stop forwarding.
*/
func (d *Dumper) portForwardPod(ctx context.Context, pod corev1.Pod, localPort string, remotePort string) (int, error) {
	if localPort == "" {
		localPort = remotePort
	}

	localPortParsed, err := strconv.ParseInt(localPort, 10, 32)
	if err != nil {
		return 0, fmt.Errorf("failed to parse port: %s with err: %s", localPort, err)
	}

	gotRemotePort, loaded := d.usedPorts.LoadOrStore(localPortParsed, remotePort)
	if loaded && gotRemotePort == remotePort {
		return int(localPortParsed), ERR_PORT_ALREADY_FORWARDED
	} else if loaded && gotRemotePort != remotePort {
		return 0, ERR_LOCAL_PORT_IN_USE
	}

	apiURL, err := url.Parse(d.restConfig.Host)
	if err != nil {
		return 0, fmt.Errorf("failed to parse config host URL: %w", err)
	}

	urlPath := path.Join(apiURL.Path, "/api/v1/namespaces/", pod.Namespace, "/pods/", pod.Name, "/portforward")
	hostURL := url.URL{
		Scheme: apiURL.Scheme,
		Host:   apiURL.Host,
		Path:   urlPath,
	}

	roundTripper, upgrader, err := spdy.RoundTripperFor(d.restConfig)
	if err != nil {
		return 0, fmt.Errorf("failed to create roundtripper and upgrader: %w", err)
	}
	dialer := spdy.NewDialer(upgrader, &http.Client{Transport: roundTripper}, http.MethodPost, &hostURL)
	readyChan := make(chan struct{}, 1)
	out, errOut := new(bytes.Buffer), new(bytes.Buffer)

	log.Infof("start frowarder for %s:%s", localPort, remotePort)
	forwarderCtx, forwarderClose := context.WithCancel(ctx)
	forwarder, err := portforward.New(dialer, []string{localPort + ":" + remotePort}, forwarderCtx.Done(), readyChan, out, errOut)
	if err != nil {
		forwarderClose()
		return 0, fmt.Errorf("failed to create port forwarder: %w", err)
	}

	go func() {
		if err = forwarder.ForwardPorts(); err != nil {
			log.Errorf("port forwarding failed: %v", err)
		}
		forwarderClose()
	}()

	select {
	case <-readyChan:
		forwardedPorts, err := forwarder.GetPorts()
		if err != nil {
			return 0, fmt.Errorf("failed to get forwarded ports: %w", err)
		}
		if len(forwardedPorts) == 0 {
			return 0, fmt.Errorf("no ports were forwarded")
		}

		localPort := int(forwardedPorts[0].Local)

		return localPort, nil
	case <-forwarderCtx.Done():
		return 0, fmt.Errorf("port forward stopped unexpectedly before being ready: %s", errOut.String())
	}
}

/*
Executes a command in the pod and returns the standard output and error streams.
The argument 'stdin' is used for piping and can be set to nil if not required.

an example of command is: command := []string{"psql", "-X", "-f", "-"}

The container can be an empty string, but the following rules will be applied:

1. If the pod has only one container, the command will be executed in that container.

2. If the pod has multiple containers, it will attempt to use the
container specified by the 'kubectl.kubernetes.io/default-container' annotation on the pod, if present.

3. If no annotation is present and there are multiple containers, this will return an error.
*/
func (d *Dumper) executeInPod(ctx context.Context, command []string, pod corev1.Pod, container string, stdin io.Reader) (bytes.Buffer, bytes.Buffer, error) {
	stdinFlag := false
	if stdin != nil {
		stdinFlag = true
	}
	var outb, errb bytes.Buffer
	req := d.clientSet.CoreV1().RESTClient().Post().
		Resource("pods").
		Name(pod.Name).
		Namespace(pod.Namespace).
		SubResource("exec").
		VersionedParams(&corev1.PodExecOptions{
			Command:   command,
			Stdin:     stdinFlag,
			Stdout:    true,
			Stderr:    true,
			TTY:       false,
			Container: container,
		}, scheme.ParameterCodec)

	exec, err := remotecommand.NewSPDYExecutor(d.restConfig, "POST", req.URL())
	if err != nil {
		return outb, errb, fmt.Errorf("error creating SPDY executor: %w", err)
	}

	err = exec.StreamWithContext(ctx, remotecommand.StreamOptions{
		Stdin:  stdin,
		Stdout: &outb,
		Stderr: &errb,
		Tty:    false,
	})
	if err != nil {
		return outb, errb, fmt.Errorf("error executing remote command: %w", err)
	}

	return outb, errb, nil
}

// tarFromPod executes tar command in pod and returns tar reader and read closer.
func (d *Dumper) tarFromPod(
	ctx context.Context,
	pod corev1.Pod,
	container string,
	args ...string,
) (*tar.Reader, io.ReadCloser, error) {
	cmd := append([]string{"tar", "cf", "-"}, args...)

	stdout, err := d.executeInPodStream(ctx, cmd, pod, container, nil)
	if err != nil {
		return nil, nil, err
	}

	return tar.NewReader(stdout), stdout, nil
}

// DrainCloser wraps an io.ReadCloser to ensure proper closure of pod exec streams.
// Kubernetes SPDY transport may try to write to a closed pipe if stdout is closed
// before fully read, causing "io: read/write on closed pipe" logs.
// Close() drains the remaining data to io.Discard to avoid these errors.
type DrainCloser struct{ io.ReadCloser }

func (d DrainCloser) Close() error {
	if d.ReadCloser == nil {
		return nil
	}
	_, _ = io.Copy(io.Discard, d.ReadCloser)
	err := d.ReadCloser.Close()
	d.ReadCloser = nil
	return err
}

// executeInPodStream executes command in pod and streams the output.
// Streaming errors are logged from the background goroutine because they can
// happen after this function has already returned the stdout reader.
func (d *Dumper) executeInPodStream(ctx context.Context, command []string, pod corev1.Pod, container string, stdin io.Reader) (io.ReadCloser, error) {
	stdinFlag := stdin != nil
	var stderr bytes.Buffer

	req := d.clientSet.CoreV1().RESTClient().Post().
		Resource("pods").
		Name(pod.Name).
		Namespace(pod.Namespace).
		SubResource("exec").
		VersionedParams(&corev1.PodExecOptions{
			Command:   command,
			Stdin:     stdinFlag,
			Stdout:    true,
			Stderr:    true,
			TTY:       false,
			Container: container,
		}, scheme.ParameterCodec)

	exec, err := remotecommand.NewSPDYExecutor(d.restConfig, "POST", req.URL())
	if err != nil {
		return nil, fmt.Errorf("error creating SPDY executor: %w", err)
	}

	pr, pw := io.Pipe()

	go func() {
		if err := exec.StreamWithContext(ctx, remotecommand.StreamOptions{
			Stdin:  stdin,
			Stdout: pw,
			Stderr: &stderr,
			Tty:    false,
		}); err != nil && !errors.Is(err, context.Canceled) {
			if stderr.Len() > 0 {
				log.Errorf("error while streaming files from pod: %s (stderr: %s)", err, stderr.String())
				_ = pw.CloseWithError(fmt.Errorf("%w: %s", err, strings.TrimSpace(stderr.String())))
				return
			}
			log.Errorf("error while streaming files from pod: %s", err)
			_ = pw.CloseWithError(err)
			return
		}

		_ = pw.Close()
	}()

	return DrainCloser{pr}, nil
}

// ParseEnvsFromSpec parses environment variables in input string
func (d *Dumper) ParseEnvsFromSpec(ctx context.Context, namespace, podName, container, input string) (string, error) {
	if !strings.Contains(input, "$") {
		return input, nil
	}

	pod, err := d.clientSet.CoreV1().Pods(namespace).Get(ctx, podName, metav1.GetOptions{})
	if err != nil {
		return "", err
	}

	for _, c := range pod.Spec.Containers {
		if c.Name == container {
			resolved := input
			for _, e := range c.Env {
				resolved = strings.ReplaceAll(resolved, "$"+e.Name, e.Value)
			}
			return resolved, nil
		}
	}

	return "", fmt.Errorf("container %s not found in pod %s", container, podName)
}
