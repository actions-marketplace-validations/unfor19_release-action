package main

import (
	"fmt"
	"html/template"
	"io/ioutil"
	"log"
	"os"
	"strings"

	"gopkg.in/yaml.v3"
)

var templateSuffix = ".tpl"
var templateBaseDir = "templates"

type LangTemplate struct {
	LangName    string
	LangVersion string
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

func main() {
	d, err := readTemplate("templates/templates.yml")
	if err != nil {
		log.Fatal(err)
	}

	for _, lang := range d.Languages {
		for _, version := range lang.Versions {
			for _, filePath := range lang.Structure {
				os.MkdirAll(filePath, 0600)
				if strings.HasSuffix(filePath, templateSuffix) {
					data, err := ioutil.ReadFile(templateBaseDir + "/" + filePath)
					if err != nil {
						log.Fatalln(err)
					}
					tmpl, _ := template.New(lang.Name + "" + version).Parse(string(data))
					t := LangTemplate{
						LangName:    lang.Name,
						LangVersion: version,
					}
					err = tmpl.Execute(os.Stdout, t)
					if err != nil {
						log.Fatalln(err)
					}
				}
			}
		}
	}

}
