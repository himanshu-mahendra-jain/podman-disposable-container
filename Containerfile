FROM docker.io/library/alpine:latest

RUN apk add --no-cache openssh-client ca-certificates \
    && addgroup -g 1000 -S disposable-container \
    && adduser -u 1000 -S -G disposable-container -h /home/disposable-container disposable-container \
    && mkdir -p /home/disposable-container/.ssh \
    && printf '%s\n' \
        'Host *' \
        '    IdentityFile /home/disposable-container/.ssh/test' \
        '    IdentitiesOnly yes' \
        '    StrictHostKeyChecking accept-new' \
        '    UserKnownHostsFile /tmp/known_hosts' \
        > /home/disposable-container/.ssh/config \
    && chown -R disposable-container:disposable-container /home/disposable-container \
    && chmod 700 /home/disposable-container/.ssh \
    && chmod 600 /home/disposable-container/.ssh/config

USER disposable-container
WORKDIR /home/disposable-container

CMD ["/bin/sh"]
