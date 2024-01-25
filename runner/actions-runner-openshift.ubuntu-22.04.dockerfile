FROM gcr.io/kaniko-project/executor AS kaniko

FROM ghcr.io/actions/actions-runner:latest

#
# Add kaniko to this image by re-using binaries and steps from official image
#
COPY --from=kaniko /kaniko /kaniko
RUN sudo chown -R runner:runner /kaniko

ENV PATH $PATH:/usr/local/bin:/kaniko
ENV DOCKER_CONFIG /kaniko/.docker/
ENV DOCKER_CREDENTIAL_GCR_CONFIG /kaniko/.config/gcloud/docker_credential_gcr_config.json
