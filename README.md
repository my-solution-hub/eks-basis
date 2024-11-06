# eks-basis

```shell
export TFSTATE_KEY=xxx # e.g. export TFSTATE_KEY=solutions/adot-gateway
export TFSTATE_BUCKET=$(aws s3 ls --output text | awk '{print $3}' | grep tfstate-)
export TFSTATE_REGION=xxx # e.g. ap-southeast-1

terraform init -backend-config="bucket=${TFSTATE_BUCKET}" -backend-config="key=${TFSTATE_KEY}" -backend-config="region=${TFSTATE_REGION}"

```
