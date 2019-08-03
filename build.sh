#!/usr/bin/env bash

set -ex

TAGS=(latest \
      asterisk-16 \
      asterisk-13 \
)

for TAG in "${TAGS[@]}"; do
  IMAGE="andrius/crystal-lang:${TAG:-latest}"
  DOCKERFILE="Dockerfile-${TAG}"
  echo "Builgind image ${IMAGE} from ${DOCKERFILE}"

  docker build --pull --force-rm --tag ${IMAGE} --file ./${DOCKERFILE} .
  docker push ${IMAGE}
done

# docker rmi -f andrius/crystal-lang:asterisk \
#               $(grep FROM Dockerfile-* | cut -d' ' -f 2 | uniq)
