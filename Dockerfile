FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application files
COPY . .

# Build Next.js app
RUN npm run build

# Expose port
EXPOSE 3000

# Start application
CMD ["npm", "start"]