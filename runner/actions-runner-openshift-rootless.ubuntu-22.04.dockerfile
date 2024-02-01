FROM --platform=linux/amd64  gcr.io/kaniko-project/executor AS kaniko
FROM --platform=linux/amd64  mcr.microsoft.com/dotnet/runtime-deps:6.0 as build

# From GitHub ARC custom image doc: https://docs.github.com/en/enterprise-cloud@latest/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/about-actions-runner-controller#creating-your-own-runner-image

# Replace value with the latest runner release version
# source: https://github.com/actions/runner/releases
# ex: 2.303.0
ARG RUNNER_VERSION=2.312.0
ARG RUNNER_ARCH="x64"
# Replace value with the latest runner-container-hooks release version
# source: https://github.com/actions/runner-container-hooks/releases
# ex: 0.3.1
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.5.0

ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

RUN apt update -y && apt install curl unzip git -y

RUN adduser --disabled-password --gecos "" runner

WORKDIR /home/runner

RUN curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz

RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

#
# Add kaniko to this image by re-using binaries and steps from official image
#
COPY --from=kaniko /kaniko /kaniko
RUN chown -R runner:runner /kaniko
ENV PATH $PATH:/usr/local/bin:/kaniko
ENV DOCKER_CONFIG /kaniko/.docker/

# Support arbitrary UIDs in Openshift 
# https://docs.openshift.com/container-platform/4.14/openshift_images/create-images.html#use-uid_create-images
RUN chgrp -R 0 /home/runner && \
    chmod -R g=u /home/runner && \
    chgrp -R 0 /kaniko && \
    chmod -R g=u /kaniko

USER runner

# Important otherwise ~/ will resolve to /, hence breaking actions that try
# to use the home directory (e.g. setup-java wants to create ~/.m2 dir)
ENV HOME=/home/runner
