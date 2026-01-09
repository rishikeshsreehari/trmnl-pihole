#### Run

docker run \
  --publish 8002:4567 \
  --volume "$(pwd):/plugin" \
  trmnl/trmnlp serve