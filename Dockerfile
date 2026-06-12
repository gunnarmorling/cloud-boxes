#
#  SPDX-License-Identifier: Apache-2.0
#
#  Copyright The original authors
#
#  Licensed under the Apache Software License version 2.0, available at http://www.apache.org/licenses/LICENSE-2.0
#

FROM quay.io/fedora/fedora-minimal:43

RUN microdnf install -y --nodocs \
      curl \
      git \
      gh \
      jq \
      zip \
      unzip \
      tar \
      diffutils \
      binutils \
      file \
      vim-common \
      python3 \
      python3-pip \
    && microdnf clean all

# Install Claude Code (native installer)
RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/root/.local/bin:$PATH"

WORKDIR /workspace

CMD ["claude"]
