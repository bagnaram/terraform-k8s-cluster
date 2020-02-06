k8s_cluster =  {
  cluster_name ="test"
  dns_zone = "test.net" # Use k8s.local for non route53 records
  worker_node_type = "t3.large"
  min_worker_nodes  = 1
  max_worker_nodes = 3
  master_node_type  = "t3.medium"
  region = "us-west-1"
  state_bucket = "kops-state"
  node_image = "kope.io/k8s-1.12-debian-stretch-amd64-hvm-ebs-2019-05-13"
  nodes = [
    {
      name = "nodes",
      role = "agent",
      instanceType = "t3.large"
      minSize = 1,
      maxSize = 5,
    }
  ]
  # List of available addons: https://github.com/kubernetes/kops/tree/master/addons
  addons = [
    "metrics-server"
  ]
}