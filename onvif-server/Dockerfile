FROM node:18-alpine

# Install git and bash (needed for run.sh)
RUN apk add --no-cache git bash iproute2 udhcpc

# Clone the onvif-server and install dependencies
RUN git clone https://github.com/daniela-hase/onvif-server /app
WORKDIR /app
RUN npm install

# Install dashboard dependencies
COPY dashboard/ /dashboard/
WORKDIR /dashboard
RUN npm install --omit=dev
WORKDIR /app

# Copy udhcpc hook script
COPY udhcpc-script /usr/bin/udhcpc-onvif-script
RUN chmod +x /usr/bin/udhcpc-onvif-script

# Copy our startup script
COPY run.sh /run.sh
RUN chmod +x /run.sh

CMD ["/run.sh"]
