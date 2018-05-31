FROM alpine:3.7
RUN apk -v --update add \
        python3 \
        curl \
        bash \
        && \
    pip3 install --upgrade pip && \
    pip3 install --upgrade awscli s3cmd && \
    rm /var/cache/apk/*

RUN curl -L https://github.com/ericchiang/pup/releases/download/v0.4.0/pup_v0.4.0_linux_amd64.zip -O && \
  unzip pup*.zip && \
  mv pup /usr/bin && \
  rm -f pup_v0.4*

VOLUME /root/.aws

ADD run.sh /run.sh

ENTRYPOINT [ "/run.sh" ]
