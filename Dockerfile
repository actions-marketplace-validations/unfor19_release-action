ARG DOCKER_IMAGE_TAG

FROM ghcr.io/unfor19/release-action:"${DOCKER_IMAGE_TAG}"
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
