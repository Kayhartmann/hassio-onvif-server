FROM node:18-alpine

# Install git and bash (needed for run.sh)
RUN apk add --no-cache git bash

# Clone the onvif-server and install dependencies
RUN git clone https://github.com/daniela-hase/onvif-server /app
WORKDIR /app
RUN npm install

# Copy our startup script
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
