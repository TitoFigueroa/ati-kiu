# Dockerfile
FROM node:latest

# Create app directory
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

COPY ../app/package*.json  /usr/src/app
COPY ../app/app.js /usr/src/app/

RUN npm install mysql2 express body-parser /usr/src/app

EXPOSE 3000

CMD ["npm", "start"]
