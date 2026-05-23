FROM mcr.microsoft.com/devcontainers/go:1.26-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       awscli \
       make \
       unzip \
       zip \
       jq \
       netcat-openbsd \
       telnet \
       less \
       ca-certificates \
       curl \
    && rm -rf /var/lib/apt/lists/*

RUN ARCH="$(dpkg --print-architecture)" \
    && case "${ARCH}" in \
         amd64) SAM_ARCH="x86_64" ;; \
         arm64) SAM_ARCH="arm64" ;; \
         *) echo "Unsupported architecture: ${ARCH}" && exit 1 ;; \
       esac \
    && curl -fsSL "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-${SAM_ARCH}.zip" -o /tmp/sam.zip \
    && unzip -q /tmp/sam.zip -d /tmp/sam-install \
    && /tmp/sam-install/install \
    && rm -rf /tmp/sam.zip /tmp/sam-install
