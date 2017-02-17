package versioncheck

import (
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	uuid "github.com/satori/go.uuid"
	log "github.com/sirupsen/logrus"
)

const (
	PERCONA_TOOLKIT = "Percona::Toolkit"
	DEFAULT_TIMEOUT = 3 * time.Second
	DEFAULT_URL     = "https://v.percona.com/"

	URL_ENV_VAR     = "PERCONA_VERSION_CHECK_URL"
	TIMEOUT_ENV_VAR = "PERCONA_VERSION_CHECK_TIMEOUT"
)

type Advice struct {
	Hash     string
	ToolName string
	Advice   string
}

func CheckUpdates(toolName, version string) (string, error) {
	url := DEFAULT_URL
	timeout := DEFAULT_TIMEOUT

	log.Info("Checking for updates")
	if envURL := os.Getenv(URL_ENV_VAR); envURL != "" {
		url = envURL
		log.Infof("Using %s env var", URL_ENV_VAR)
	}

	if envTimeout := os.Getenv(TIMEOUT_ENV_VAR); envTimeout != "" {
		i, err := strconv.Atoi(envTimeout)
		if err == nil && i > 0 {
			log.Infof("Using time out from %s env var", TIMEOUT_ENV_VAR)
			timeout = time.Millisecond * time.Duration(i)
		}
	}

	log.Infof("Contacting version check API at %s. Timeout set to %v", url, timeout)
	return checkUpdates(url, timeout, toolName, version)
}

func checkUpdates(url string, timeout time.Duration, toolName, version string) (string, error) {

	client := &http.Client{
		Timeout: timeout,
	}
	payload := fmt.Sprintf("%x;%s;%s", uuid.NewV2(uuid.DomainOrg).String(), PERCONA_TOOLKIT, version)
	req, err := http.NewRequest("POST", url, strings.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Add("Accept", "application/json")
	req.Header.Add("X-Percona-Toolkit-Tool", toolName)
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}

	log.Debug(resp.Status)
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}
	advices := []Advice{}
	err = json.Unmarshal(body, &advices)
	if err != nil {
		return "", err
	}

	for _, advice := range advices {
		if advice.ToolName == PERCONA_TOOLKIT {
			return advice.Advice, nil
		}
	}

	return "", nil
}
