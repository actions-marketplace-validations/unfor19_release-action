package main

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"html/template"
	"io"
	"io/ioutil"
	"log"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/docker/docker/api/types"
	"github.com/docker/docker/client"
	"github.com/docker/docker/pkg/jsonmessage"
	"github.com/docker/docker/pkg/term"
	"gopkg.in/yaml.v3"
)

var templateYmlPath = "templates/templates.yml"
var templateSuffix = ".tpl"
var templateBaseDir = "templates"
var alpineVersion = "3.13"
var dockerRegistryUserID = "ghcr.io/unfor19"
var dockerImageName = "release-action"
var dockerFileTemplateName = "Dockerfile.base.tpl"

type ErrorLine struct {
	Error       string      `json:"error"`
	ErrorDetail ErrorDetail `json:"errorDetail"`
}

type ErrorDetail struct {
	Message string `json:"message"`
}

type LangTemplate struct {
	LangName      string
	LangVersion   string
	AlpineVersion string
}

type Language struct {
	Name      string   `yaml:"name"`
	Versions  []string `yaml:"versions"`
	Structure []string `yaml:"structure"`
}

type Template struct {
	Languages []Language
}

func readTemplate(filePath string) (*Template, error) {
	buf, err := ioutil.ReadFile(filePath)
	if err != nil {
		return nil, err
	}
	c := &Template{}
	err = yaml.Unmarshal(buf, c)
	if err != nil {
		return nil, fmt.Errorf("Error in %q: %v", filePath, err)
	}

	return c, nil
}

func dockerLogger(rd io.Reader) {
	termFd, isTerm := term.GetFdInfo(os.Stderr)
	jsonmessage.DisplayJSONMessagesStream(rd, os.Stderr, termFd, isTerm, nil)
}

func dockerImageBuild(dockerClient *client.Client, t *LangTemplate, dockerFileName string) error {

	langBaseImage := t.LangName + ":" + t.LangVersion + "-" + "alpine" + alpineVersion

	ctx, cancel := context.WithTimeout(context.Background(), time.Second*120)
	defer cancel()

	buf := new(bytes.Buffer)
	tw := tar.NewWriter(buf)
	defer tw.Close()

	args := map[string]*string{
		"LANG_IMAGE":     &langBaseImage,
		"ALPINE_VERSION": &alpineVersion,
	}

	cwd, err := os.Getwd()
	if err != nil {
		log.Fatalln("Failed to get working dir", err)
	}
	dockerfilePath := cwd + "/" + dockerFileName
	dockerFileReader, err := os.Open(dockerfilePath)
	if err != nil {
		log.Fatal(err, " :unable to open Dockerfile")
	}
	readDockerFile, err := ioutil.ReadAll(dockerFileReader)
	if err != nil {
		log.Fatal(err, " :unable to read dockerfile")
	}

	tarHeader := &tar.Header{
		Name: dockerFileName,
		Size: int64(len(readDockerFile)),
	}
	err = tw.WriteHeader(tarHeader)
	if err != nil {
		log.Fatal(err, " :unable to write tar header")
	}
	_, err = tw.Write(readDockerFile)
	if err != nil {
		log.Fatal(err, " :unable to write tar body")
	}
	dockerFileTarReader := bytes.NewReader(buf.Bytes())

	tags := []string{dockerRegistryUserID + "/" + dockerImageName + ":" + t.LangName + "-" + t.LangVersion}
	imageBuildResponse, err := dockerClient.ImageBuild(
		ctx,
		dockerFileTarReader,
		types.ImageBuildOptions{
			Context:    dockerFileTarReader,
			Dockerfile: dockerFileName,
			Remove:     true,
			Tags:       tags,
			BuildArgs:  args,
		})
	if err != nil {
		log.Fatal(err, " :unable to build docker image")
	}
	defer imageBuildResponse.Body.Close()
	dockerLogger(imageBuildResponse.Body)
	return nil
}

func dockerImagePush(authConfig types.AuthConfig, dockerClient *client.Client, tag string) error {
	ctx, cancel := context.WithTimeout(context.Background(), time.Second*120)
	defer cancel()

	authConfigBytes, _ := json.Marshal(authConfig)
	authConfigEncoded := base64.URLEncoding.EncodeToString(authConfigBytes)

	opts := types.ImagePushOptions{RegistryAuth: authConfigEncoded}
	dockerPushResponse, err := dockerClient.ImagePush(ctx, tag, opts)
	if err != nil {
		log.Fatalln("Failed to push Docker image", err)
		return err
	}

	defer dockerPushResponse.Close()
	dockerLogger(dockerPushResponse)
	return nil
}

func ParseTplFile(srcFilePath string, outputFilePath string, templateName string, templateInterface interface{}) error {
	data, err := ioutil.ReadFile(srcFilePath)
	if err != nil {
		return err
	}
	outputFile, err := os.Create(outputFilePath)
	outputFile.Chmod(0755)
	defer outputFile.Close()
	if err != nil {
		return err
	}
	if strings.HasSuffix(srcFilePath, templateSuffix) {
		tmpl, _ := template.New(templateName).Parse(string(data))
		err = tmpl.Execute(outputFile, templateInterface)
		if err != nil {
			return err
		}
	} else {
		outputFile.Write([]byte(data))
	}
	return nil
}

func main() {
	d, err := readTemplate(templateYmlPath)
	if err != nil {
		log.Fatal(err)
	}
	authConfig := types.AuthConfig{
		Username: "oauth2accesstoken",
		Password: os.Getenv("DOCKER_TOKEN"),
	}

	for _, lang := range d.Languages {
		for _, version := range lang.Versions {
			cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
			if err != nil {
				fmt.Println(err.Error())
				return
			}
			langTemplate := LangTemplate{
				LangName:      lang.Name,
				LangVersion:   version,
				AlpineVersion: alpineVersion,
			}
			dockerfileBaseName := strings.ReplaceAll(dockerFileTemplateName, ".tpl", "")
			err = ParseTplFile(dockerFileTemplateName, dockerfileBaseName, dockerImageName, langTemplate)
			if err != nil {
				log.Fatalln("Failed to parse Docker base file", dockerFileTemplateName, err)
			}

			err = dockerImageBuild(cli, &langTemplate, dockerfileBaseName)
			if err != nil {
				log.Fatalln("Failed to build docker image", err)
			}
			tag := dockerRegistryUserID + "/" + dockerImageName + ":" + lang.Name + "-" + version
			err = dockerImagePush(authConfig, cli, tag)
			if err != nil {
				log.Fatalln("Failed to push Docker image", err)
			}

			for _, filePath := range lang.Structure {
				var dirPath string
				var cleanFileName string
				var fileName string
				if strings.Contains(filePath, "/") {
					dirPath = lang.Name + "/" + version + "/" + filepath.Dir(filePath)
					fileName = filepath.Base(filePath)
					cleanFileName = strings.ReplaceAll(fileName, templateSuffix, "")
				} else {
					dirPath = lang.Name + "/" + version
					fileName = filepath.Base(filePath)
					cleanFileName = strings.ReplaceAll(filePath, templateSuffix, "")
				}

				os.MkdirAll(dirPath, 0755)
				outputFilePath := dirPath + "/" + cleanFileName
				err = ParseTplFile(templateBaseDir+"/"+filePath, outputFilePath, lang.Name+version, LangTemplate{
					LangName:    lang.Name,
					LangVersion: version,
				})
				if err != nil {
					log.Fatalln("Error parsing template file", err)
				}
			}
		}
	}

}
