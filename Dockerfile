FROM crystallang/crystal:0.29.0-build

RUN \
apt-get update && \
apt-get install --no-install-recommends --no-install-suggests -yqq \
  curl \
  dnsutils \
  iputils-ping \
  libc-dev \
  libpq-dev \
  libsqlite3-dev \
  ngrep \
  mc \
  tmux \
  vim-nox \
&& : \
cd /tmp && \
git clone https://github.com/crystal-community/icr.git && \
cd icr && \
make && \
make install && \
cd .. && \
rm -rf icr && \
icr --disable-update-check && \
\
apt-get clean all && \
rm -rf /tmp/* \
       /var/tmp/* \
       /var/lib/apt/lists/*

CMD ["icr", "-r", "colorize", "-r"]
