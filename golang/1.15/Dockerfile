FROM ghcr.io/unfor19/release-action:golang-1.15
RUN go get -u github.com/vakenbolt/go-test-report
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
