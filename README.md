
# Actions Runner Controller (ARC)

## ARC on OCP Fork Documentation


### Goals
* Run ARC on Openshift without defeating the Openshift security
* Be able to build container images in Actions workflows run by ARC runners
    * [Kaniko](https://github.com/GoogleContainerTools/kaniko) will be used since it does not require root privilege on the cluster nodes

### What has been done so far
* Created **two** Dockerfile for the ARC runners on OCP;
	 * one with root access through `sudo` ([Dockerfile](./runner/actions-runner-openshift.ubuntu-22.04.dockerfile)):
	    * the image is based on [the default runner image](https://ghcr.io/actions/actions-runner:latest) and includes all the kaniko tooling;
	    * image is [publicly available](https://github.com/orgs/ghsioux-octodemo/packages/container/package/actions-runner-controller%2Farc-runner-ocp)
	    * **pros:** developpers will be able to run `sudo` commands (e.g. `sudo apt install`) directly in their Actions workflows if needed;
	     * **cons:** will require [`anyuid` SCC](https://docs.openshift.com/container-platform/4.14/authentication/managing-security-context-constraints.html) (see How to below) which is not a good practice in an Openshift environment (defeats the Openshift security);
	 * one fully rootless ([Dockerfile](./runner/actions-runner-openshift-rootless.ubuntu-22.04.dockerfile)):
	    * the image is based on [the official doc to build custom ARC runner image](https://docs.github.com/en/enterprise-cloud@latest/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/about-actions-runner-controller#creating-your-own-runner-image) and includes all the kaniko tooling;
	    * image is [publicly available](https://github.com/orgs/ghsioux-octodemo/packages/container/package/actions-runner-controller%2Farc-runner-ocp-rootless)	    
	    * **pros:** will require a custom, least-privileged SCC (see How to below) which is a good practice in an Openshift environment (no root or privilege needed);
	     * **cons:** the packages required to run the workflows must be installed in [the Dockerfile](https://github.com/ghsioux-octodemo/actions-runner-controller/blob/master/runner/actions-runner-openshift-rootless.ubuntu-22.04.dockerfile#L18);
 * Created 2 Helm values file for the runner set on Openshift
	 * the only difference is actually the image used by the runner
	   * one [values file for the root-enabled image](./charts/gha-runner-scale-set/values-openshift.yaml);
	   * one [values file for the rootless image](./charts/gha-runner-scale-set/values-openshift-rootless.yaml);
 * Created [a custom SCC `uid1001`](./uid1001.yaml) to allow the runner pods to run with the `runner` user in a secure way (without root access); 
 * Created [`kaniko-*` actions](https://github.com/ghsioux-octodemo/arc-on-openshift-test-actions-workflow/tree/main/.github/actions) for login to private registry and build/push image;
 * Created [a sample workflow](https://github.com/ghsioux-octodemo/arc-on-openshift-test-actions-workflow/blob/main/.github/workflows/arc-runner-set-ocp-test-with-actions.yml) to test the whole setup by building a simple container image and pushing it to GHCR.

### TODO

* Update the runner set Helm chart to automate the SCC creation / binding
* Improve the `kaniko-build-push` action to handle more cases

## How-to

### Create a local Openshift Cluster using CRC
1. Download CRC from [Red Hat website](https://developers.redhat.com/products/openshift-local/overview)
2. `crc setup`
	* you'll need the pull secret that you can retrieve from the Red Hat portal
3. `crc start`
4. Once the cluster has started, run `crc console --credentials` to retrieve the command line to authenticate as cluster admin
5. `oc login -u kubeadmin -p hR5Dp.....dYIrS-zDu6V https://api.crc.testing:6443` 

#### Install the ARC controller
There is nothing to modify compared to the default [ARC controller install on K8S](https://docs.github.com/en/enterprise-cloud@latest/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller#installing-actions-runner-controller):

```
NAMESPACE="arc-systems"
helm install arc \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

#### Prepare the runner auth secret using the GitHub app info

We use the [GitHub app auth method](https://docs.github.com/en/enterprise-cloud@latest/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/authenticating-to-the-github-api#authenticating-arc-with-a-github-app) to authenticate ARC runners to GitHub.

```
$ APP_ID=793817
$ INSTALL_ID=46003824
$ GPG_KEY=./gpg.key # the gpg key file is retrieved from GitHub.com and stored locally

$ oc new-project arc-runners
$ oc create secret generic pre-defined-secret \
   --namespace=arc-runners \
   --from-literal=github_app_id=$APP_ID \
   --from-literal=github_app_installation_id=$INSTALL_ID \
   --from-file=github_app_private_key=$GPG_KEY
```

#### Deploy the ARC runner set for OCP (root version)

```bash
$ INSTALLATION_NAME="arc-runner-set-ocp"
NAMESPACE="arc-runners"
helm upgrade --install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --values ./charts/gha-runner-scale-set/values-openshift.yaml \
    --set githubConfigUrl="https://github.com/ghsioux-octodemo" \
    --set githubConfigSecret="pre-defined-secret" \
    --set minRunners=1 \
    ./charts/gha-runner-scale-set

# Allow the runners to use sudo and anyuid
# By default, the runner process runs with UID 1001 but it can do sudo for certain tasks 
$ oc adm policy add-scc-to-user anyuid -z arc-runner-set-ocp-gha-rs-no-permission -n arc-runners
```

#### Deploy the ARC runner set for OCP (rootless version)
```bash
$ INSTALLATION_NAME="arc-runner-set-ocp"
NAMESPACE="arc-runners"
helm upgrade --install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --values ./charts/gha-runner-scale-set/values-openshift-rootless.yaml \
    --set githubConfigUrl="https://github.com/ghsioux-octodemo" \
    --set githubConfigSecret="pre-defined-secret" \
    --set minRunners=1 \
    ./charts/gha-runner-scale-set

# Create the custom SCC
$ oc apply -f uid1001.yaml

# By default, the runner process runs with UID 1001 but it can do sudo for certain tasks 
$ oc adm policy add-scc-to-user uid1001 -z arc-runner-set-ocp-gha-rs-no-permission -n arc-runners
```

#### Test the setup
Go to [the Actions tab of the test repository](https://github.com/ghsioux-octodemo/arc-on-openshift-test-actions-workflow/actions/workflows/arc-runner-set-ocp-test-with-actions.yml) (where the kaniko actions and test workflow resides) and trigger manually the test workflow. 

## Below is the original [actions-runner-controller repo](https://github.com/actions/actions-runner-controller/) README

## About

Actions Runner Controller (ARC) is a Kubernetes operator that orchestrates and scales self-hosted runners for GitHub Actions.

With ARC, you can create runner scale sets that automatically scale based on the number of workflows running in your repository, organization, or enterprise. Because controlled runners can be ephemeral and based on containers, new runner instances can scale up or down rapidly and cleanly. For more information about autoscaling, see ["Autoscaling with self-hosted runners."](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/autoscaling-with-self-hosted-runners)

You can set up ARC on Kubernetes using Helm, then create and run a workflow that uses runner scale sets. For more information about runner scale sets, see ["Deploying runner scale sets with Actions Runner Controller."](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/deploying-runner-scale-sets-with-actions-runner-controller#runner-scale-set)
## People

Actions Runner Controller (ARC) is an open-source project currently developed and maintained in collaboration with the GitHub Actions team, external maintainers @mumoshu and @toast-gear, various [contributors](https://github.com/actions/actions-runner-controller/graphs/contributors), and the [awesome community](https://github.com/actions/actions-runner-controller/discussions).

If you think the project is awesome and is adding value to your business, please consider directly sponsoring [community maintainers](https://github.com/sponsors/actions-runner-controller) and individual contributors via GitHub Sponsors.

In case you are already the employer of one of contributors, sponsoring via GitHub Sponsors might not be an option. Just support them in other means!

See [the sponsorship dashboard](https://github.com/sponsors/actions-runner-controller) for the former and the current sponsors.

## Getting Started

To give ARC a try with just a handful of commands, Please refer to the [Quickstart guide](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller).

For an overview of ARC, please refer to [About ARC](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/about-actions-runner-controller)

With the introduction of [autoscaling runner scale sets](https://github.com/actions/actions-runner-controller/discussions/2775), the existing [autoscaling modes](./docs/automatically-scaling-runners.md) are now legacy. The legacy modes have certain use cases and will continue to be maintained by the community only.

For further information on what is supported by GitHub and what's managed by the community, please refer to [this announcement discussion.](https://github.com/actions/actions-runner-controller/discussions/2775)

### Documentation

ARC documentation is available on [docs.github.com](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/quickstart-for-actions-runner-controller).

### Legacy documentation

The following documentation is for the legacy autoscaling modes that continue to be maintained by the community

- [Quickstart guide](/docs/quickstart.md)
- [About ARC](/docs/about-arc.md)
- [Installing ARC](/docs/installing-arc.md)
- [Authenticating to the GitHub API](/docs/authenticating-to-the-github-api.md)
- [Deploying ARC runners](/docs/deploying-arc-runners.md)
- [Adding ARC runners to a repository, organization, or enterprise](/docs/choosing-runner-destination.md)
- [Automatically scaling runners](/docs/automatically-scaling-runners.md)
- [Using custom volumes](/docs/using-custom-volumes.md)
- [Using ARC runners in a workflow](/docs/using-arc-runners-in-a-workflow.md)
- [Managing access with runner groups](/docs/managing-access-with-runner-groups.md)
- [Configuring Windows runners](/docs/configuring-windows-runners.md)
- [Using ARC across organizations](/docs/using-arc-across-organizations.md)
- [Using entrypoint features](/docs/using-entrypoint-features.md)
- [Deploying alternative runners](/docs/deploying-alternative-runners.md)
- [Monitoring and troubleshooting](/docs/monitoring-and-troubleshooting.md)

## Contributing

We welcome contributions from the community. For more details on contributing to the project (including requirements), please refer to "[Getting Started with Contributing](https://github.com/actions/actions-runner-controller/blob/master/CONTRIBUTING.md)."

## Troubleshooting

We are very happy to help you with any issues you have. Please refer to the "[Troubleshooting](https://github.com/actions/actions-runner-controller/blob/master/TROUBLESHOOTING.md)" section for common issues.
