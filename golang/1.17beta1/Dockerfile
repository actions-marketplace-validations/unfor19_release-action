FROM ghcr.io/unfor19/release-action:golang-1.17beta1
ENV LANG_NAME="golang"
ENV LANG_VERSION="1.17beta1"
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
