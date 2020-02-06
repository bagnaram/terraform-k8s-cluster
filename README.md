# terraform-k8s-cluster

Deployment of Kubernetes on AWS, etc via Terraform

The goal of this page is to have a functional testbed kubernetes cluster that leverages Terraform. Terraform is an infrastructure topology tool that creates a common schema for various cloud and infrastructure providers.



## Prerequisites

* Access to cloud (ex. AWS)
* Base image used for provisioning. https://github.com/bagnaram/packer-k8s-centos
* Linux Machine:
  * `python` & `boto` for AWS
  * `terraform` https://www.terraform.io/

### AWS Considerations

IAM roles needed for the AWS cloud provider are listed in the out-of-tree repository https://github.com/kubernetes/cloud-provider-aws These roles are included in the terraform template.

## Install Terraform
Terraform provides a layered infrastructure template that can be used to deploy to different providers. This example will deploy a template to Amazon.

Download the terraform binary from Hashicorp.


## Prepare infrastructure for AWS

By default, this template will deploy an HA configured infrastructure:
3 control-plane nodes
2 worker nodes

It utilizes a base image that is common throughout the infrastructure, providing true infrastructure-as-code. This functionalty can be expanded to provide flexibility to lock down images, or to even harden to CIS benchmarks.

The template `variables.tf` will need to be modified to match your environment:
1. `aws_region` to the AWS region you specify.
2. `instance_size` to the Amazon instance type
3. `private_key` to a local SSH private key
4. `key_name` to the AWS key pair that matches the private key.

By default this template will go out and select the latest AMI which tag `OS_Version` equals `CentOS`. This guide assumes the image has been created by the guide: https://github.com/bagnaram/packer-k8s-centos

## Deploy Infrastructure to AWS

If you are running terraform for the first time, you will need to run `terraform plan` to syncronize any needed plugins.

Source the AWS credentials that you obtain from the console:
```
export AWS_SESSION_TOKEN=
export AWS_SECRET_ACCESS_KEY=
export AWS_ACCESS_KEY_ID=
```

Simply run `terraform apply` to deploy the instances. It will create all needed VPC, Subnet, ELB, EC2 instances, and resources needed for a base Kubernetes cluster.

When the execution completes, you will be presented with the ELB public DNS name. Save this value for the next `kubeadm` section.

## Install with kubeadm

The installation is mostly standard except for the optional cloud provider configuration. In this example, I use AWS but it can be substituted also. I have referenced configuration resources found in this article https://blog.scottlowe.org/2019/08/14/setting-up-aws-integrated-kubernetes-115-cluster-kubeadm/.

1. SSH into one of the control plane nodes. This will be the initial bootstrap of the Kubernetes control plane.
2. Create the following file `kubeadm.conf`. Replace `controlPlaneEndpoint` with the ELB DNS record output at the end of the terraform run.  This file is read by kubeadm to provide the base configuration necessary to initially deploy a control-plane.
```
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: v1.17.2
controlPlaneEndpoint: terraform-control-plane-elb-10124.us-west-1.elb.amazonaws.com:6443
networking:
  serviceSubnet: "10.96.0.0/12"
  podSubnet: "10.244.0.0/16"
apiServer:
  extraArgs:
    cloud-provider: aws
controllerManager:
  extraArgs:
    cloud-provider: "aws"
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: InitConfiguration
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: "aws"
```
3. Run `sudo kubeadm init --upload-certs --config=kubeadm.conf`
    1. Once this completes, capture the output of the `kubeadm init` command. There will be a control plane join command, and a worker node join command.
4. SSH into the rest of the control plane nodes. This is the stage which the intial control-plane is scaled out to the rest of the control-plane virtual machine instances.
    1. Create the following control plane node join config file `kubeadm.conf` This file is read by `kubeadm join` to provide the base configuration necessary to join an exisiting control-plane, thus, scaling it out.

    ```
    apiVersion: kubeadm.k8s.io/v1beta2
    kind: JoinConfiguration
    discovery:
    bootstrapToken:
        token: kedjasdal.2900igrlol23swyv
        apiServerEndpoint: "terraform-control-plane-elb-10124.us-west-1.elb.amazonaws.com:6443"
        caCertHashes: ["sha256:2d932d3d6f2753a082f345586bd1be479d5d0481bb1b0ce2acb00133cc6943a3"]
    nodeRegistration:
    kubeletExtraArgs:
        cloud-provider: aws
    controlPlane:
    certificateKey: "b14fd947d50d1a9a96b9c807f03284ed3fa6469efccc984aefa707cc2b118c8a"
    ```

    2. Replace the `token`, `apiServerEndpoint`, `caCertHashes` with the values recorded by the `kubeadm init` stage. These need to match so that kubeadm has the credentials needed to join the pre-existing control-plane.
    3. Run `sudo kubeadm join --config=kubeadm.conf`
5. SSH into the rest of the worker nodes. At this point, the worker node virtual machine instances are ready to join the control plane.
    1. Create the following worker node join config file `kubeadm.conf`. This file is read by `kubeadm join` to provide the base configuration necessary to join an exisiting control-plane as a worker node. Notice the difference between this snippet below and the one above it. This snippet doesn't containtain a `certificateKey` meaning it will join as a worker node.

    ```
    apiVersion: kubeadm.k8s.io/v1beta2
    kind: JoinConfiguration
    discovery:
    bootstrapToken:
        token: kedjasdal.2900igrlol23swyv
        apiServerEndpoint: "terraform-control-plane-elb-10124.us-west-1.elb.amazonaws.com:6443"
        caCertHashes: ["sha256:2d932d3d6f2753a082f345586bd1be479d5d0481bb1b0ce2acb00133cc6943a3"]
    nodeRegistration:
    kubeletExtraArgs:
        cloud-provider: aws
    ```

    2. Replace the `token`, `apiServerEndpoint`, `caCertHashes` with the values recorded by the `kubeadm init` stage. These need to match so that kubeadm has the credentials needed to join the pre-existing control-plane.
    3. Run `sudo kubeadm join --config=kubeadm.conf`
6. SSH back into the initial control plane node and verify nodes. `kubectl get nodes` Notice the nodes are still `NotReady` state. This is because the CNI (container-networking-interface) hasn't been deployed, so there is no pod network set up across nodes.
```
[centos@ip-10-0-1-124 ~]$ kubectl get nodes
NAME                                       STATUS   ROLES    AGE     VERSION
ip-10-0-1-124.us-west-1.compute.internal   NotReady    master   3h40m   v1.17.2
ip-10-0-1-181.us-west-1.compute.internal   NotReady    <none>   3h29m   v1.17.2
ip-10-0-1-218.us-west-1.compute.internal   NotReady    master   3h32m   v1.17.2
ip-10-0-1-39.us-west-1.compute.internal    NotReady    <none>   3h30m   v1.17.2
ip-10-0-1-71.us-west-1.compute.internal    NotReady    master   3h34m   v1.17.2
```
7. Deploy the Calico CNI found in the Kubernetes steps https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/ to bring the nodes into a `Ready` state.
