package dumper

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"path"
	"strconv"

	corev1 "k8s.io/api/core/v1"
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

	forwarderCtx, forwarderClose := context.WithCancel(ctx)
	forwarder, err := portforward.New(dialer, []string{localPort + ":" + remotePort}, forwarderCtx.Done(), readyChan, out, errOut)
	if err != nil {
		forwarderClose()
		return 0, fmt.Errorf("failed to create port forwarder: %w", err)
	}

	go func() {
		if err = forwarder.ForwardPorts(); err != nil {
			log.Printf("port forwarding failed: %v", err)
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
