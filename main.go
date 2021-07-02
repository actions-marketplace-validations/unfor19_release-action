package main

import (
	"archive/tar"
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
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
var dockerfileBaseName = "Dockerfile.base"

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

func print(rd io.Reader) error {
	var lastLine string

	scanner := bufio.NewScanner(rd)
	for scanner.Scan() {
		lastLine = scanner.Text()
		fmt.Println(scanner.Text())
	}

	errLine := &ErrorLine{}
	json.Unmarshal([]byte(lastLine), errLine)
	if errLine.Error != "" {
		return errors.New(errLine.Error)
	}

	if err := scanner.Err(); err != nil {
		return err
	}

	return nil
}

func dockerImageBuild(dockerClient *client.Client, t *LangTemplate) error {

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
	dockerFile := "Dockerfile.base"
	cwd, err := os.Getwd()
	if err != nil {
		log.Fatalln("Failed to get working dir", err)
	}
	dockerfilePath := cwd + "/" + dockerfileBaseName
	dockerFileReader, err := os.Open(dockerfilePath)
	if err != nil {
		log.Fatal(err, " :unable to open Dockerfile")
	}
	readDockerFile, err := ioutil.ReadAll(dockerFileReader)
	if err != nil {
		log.Fatal(err, " :unable to read dockerfile")
	}

	tarHeader := &tar.Header{
		Name: dockerFile,
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

	tags := []string{dockerRegistryUserID + dockerImageName + t.LangName + "-" + t.LangVersion}
	imageBuildResponse, err := dockerClient.ImageBuild(
		ctx,
		dockerFileTarReader,
		types.ImageBuildOptions{
			Context:    dockerFileTarReader,
			Dockerfile: dockerFile,
			Remove:     true,
			Tags:       tags,
			BuildArgs:  args,
		})
	if err != nil {
		log.Fatal(err, " :unable to build docker image")
	}
	defer imageBuildResponse.Body.Close()
	termFd, isTerm := term.GetFdInfo(os.Stderr)
	jsonmessage.DisplayJSONMessagesStream(imageBuildResponse.Body, os.Stderr, termFd, isTerm, nil)
	return nil
}

func main() {
	d, err := readTemplate(templateYmlPath)
	if err != nil {
		log.Fatal(err)
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
			err = dockerImageBuild(cli, &langTemplate)
			if err != nil {
				log.Fatalln("Failed to build docker image", err)
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

				os.MkdirAll(dirPath, 0744)
				data, err := ioutil.ReadFile(templateBaseDir + "/" + filePath)
				if err != nil {
					log.Fatalln(err)
				}

				outputFilePath := dirPath + "/" + cleanFileName

				outputFile, err := os.Create(outputFilePath)
				defer outputFile.Close()
				if err != nil {
					log.Fatalln("Error creating output file", err)
				}
				if err != nil {
					log.Fatalln(err)
				}
				if strings.HasSuffix(filePath, templateSuffix) {
					tmpl, _ := template.New(lang.Name + "" + version).Parse(string(data))
					t := LangTemplate{
						LangName:    lang.Name,
						LangVersion: version,
					}

					err = tmpl.Execute(outputFile, t)
					if err != nil {
						log.Fatalln(err)
					}
				} else {
					outputFile.Write([]byte(data))
				}
			}
		}
	}

}
