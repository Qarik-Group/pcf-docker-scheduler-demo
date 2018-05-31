#!/bin/bash

set -eu

# check AWS credentials and bucket working
S3_BASE_URI=s3://${S3_BUCKET:?required}
DILBERT_PATH=${DILBERT_PATH:-dilbert}

echo "Testing AWS credentials to access ${S3_BASE_URI}"
aws s3 ls "${S3_BASE_URI}/"

WORKDIR=${WORKDIR:-tmp}
mkdir -p "${WORKDIR}/${DILBERT_PATH}"
cd "$WORKDIR/${DILBERT_PATH}"

datestamp=$(curl -sL http://dilbert.com/ | pup "h1.comic-title a attr{href}" | head -n1 | sed -e "s%^.*/%%")
imageurl=$(curl -sL http://dilbert.com/ | pup ".img-comic-container img attr{src}" | head -n1)

echo "Found image for ${datestamp}"

mkdir -p dilbert
imagepath="${datestamp}.png"

curl -sL "${imageurl}" -o "${imagepath}"

echo "Uploading to ${S3_BASE_URI}"
aws s3 sync . "${S3_BASE_URI}/${DILBERT_PATH}/"
