FROM ghcr.io/unfor19/release-action:golang-1.15
RUN go get -u github.com/jstemmer/go-junit-report
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
