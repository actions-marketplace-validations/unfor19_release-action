FROM ghcr.io/unfor19/release-action:golang-1.17beta1
RUN wget -O /tmp/go-test-report.tgz "https://github.com/vakenbolt/go-test-report/releases/download/v0.9.3/go-test-report-linux-v0.9.3.tgz" && \
    tar -xzf /tmp/go-test-report.tgz && \
    mv go-test-report /usr/local/bin/go-test-report && \
    chmod +x /usr/local/bin/go-test-report && \
    rm  go-test-report*
WORKDIR /code/
COPY ./src/ .
ENTRYPOINT ["/code/entrypoint.sh"]
