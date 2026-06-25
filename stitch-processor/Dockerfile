FROM node:22-alpine

RUN apk add --no-cache su-exec

WORKDIR /app
COPY package.json .
RUN npm install --omit=dev && npm cache clean --force

COPY index.js .
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8082
ENTRYPOINT ["/entrypoint.sh"]
CMD ["node", "index.js"]
