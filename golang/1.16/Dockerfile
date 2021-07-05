FROM ghcr.io/unfor19/release-action:golang-1.16
ENV LANG_NAME="golang" LANG_VERSION="1.16"
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
