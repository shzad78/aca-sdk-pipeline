FROM ubuntu:22.04

WORKDIR /opt/sdk

COPY sdk/sdk-extracted /opt/sdk

ENV PATH=/opt/sdk/bin:$PATH

CMD ["bash"]