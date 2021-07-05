FROM ghcr.io/unfor19/release-action:golang-1.15
ENV LANG_NAME="golang"
ENV LANG_VERSION="1.15"
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
