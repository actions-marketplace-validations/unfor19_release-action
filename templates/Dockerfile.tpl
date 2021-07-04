FROM ghcr.io/unfor19/release-action:{{.LangName}}-{{.LangVersion}}
{{- if eq .LangName "golang" }}
RUN go get -u github.com/vakenbolt/go-test-report
{{- end }}
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
