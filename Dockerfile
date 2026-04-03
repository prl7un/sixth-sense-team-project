# 1. 베이스 이미지
FROM nginx:alpine

# 2. CI 성공 확인용 메시지
RUN echo "CI TEST Success!" > /usr/share/nginx/html/index.html

# 3. 실행 명령어 (기본값 사용)
CMD ["nginx", "-g", "daemon off;"]