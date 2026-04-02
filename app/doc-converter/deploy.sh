#!/bin/bash

# 1. 기존 컨테이너 정리
echo "Cleaning up old container..."
sudo docker stop sixsense-final-test 2>/dev/null
sudo docker rm sixsense-final-test 2>/dev/null

# 2. 도커 이미지 빌드
echo "Building Docker image..."
sudo docker build -t doc-converter:latest .

# 3. .env 파일 존재 여부 확인 및 컨테이너 실행
if [ ! -f .env ]; then
    echo "Error: .env file not found."
    exit 1
fi

echo "Starting container with .env configuration..."
sudo docker run -d \
  -p 8000:8000 \
  --env-file .env \
  --name sixsense-final-test \
  doc-converter:latest

# 4. 로그 실시간 확인
echo "Showing real-time logs..."
sudo docker logs -f sixsense-final-test
