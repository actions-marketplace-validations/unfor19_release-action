FROM ghcr.io/unfor19/release-action:{{.LangName}}-{{.LangVersion}}
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
