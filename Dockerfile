FROM node:20-alpine AS builder

# Instalar dependências do sistema de uma vez para melhor cache
RUN apk update && \
    apk add --no-cache git ffmpeg wget curl bash openssl dos2unix && \
    rm -rf /var/cache/apk/*

LABEL version="2.3.0" description="Api to control whatsapp features through http requests." 
LABEL maintainer="Davidson Gomes" git="https://github.com/DavidsonGomes"
LABEL contact="contato@evolution-api.com"

WORKDIR /evolution

# Copiar arquivos de configuração primeiro para melhor cache de camadas
COPY ./package.json ./package-lock.json ./tsconfig.json ./

# Install dependencies (incluindo dev dependencies para o build)
RUN npm ci --silent && \
    npm cache clean --force

# Copiar scripts do Docker primeiro e dar permissões
COPY ./Docker ./Docker
RUN chmod +x ./Docker/scripts/* && \
    find ./Docker/scripts/ -type f -exec dos2unix {} \;

# Copiar código fonte e arquivos necessários
COPY ./src ./src
COPY ./public ./public
COPY ./prisma ./prisma
COPY ./manager ./manager
COPY ./.env.example ./.env
COPY ./runWithProvider.js ./
COPY ./tsup.config.ts ./

# Gerar database e build
RUN ./Docker/scripts/generate_database.sh && \
    npm run build

FROM node:20-alpine AS final

# Instalar apenas dependências necessárias para runtime
RUN apk update && \
    apk add --no-cache tzdata ffmpeg bash openssl && \
    rm -rf /var/cache/apk/*

ENV TZ=America/Sao_Paulo
ENV DOCKER_ENV=true
ENV NODE_ENV=production

WORKDIR /evolution

# Copiar package files e instalar apenas dependências de produção
COPY --from=builder /evolution/package.json ./package.json
COPY --from=builder /evolution/package-lock.json ./package-lock.json

# Instalar apenas dependências de produção para imagem final menor
RUN npm ci --only=production --silent && \
    npm cache clean --force

# Copiar arquivos necessários do builder
COPY --from=builder /evolution/dist ./dist
COPY --from=builder /evolution/prisma ./prisma
COPY --from=builder /evolution/manager ./manager
COPY --from=builder /evolution/public ./public
COPY --from=builder /evolution/.env ./.env
COPY --from=builder /evolution/Docker ./Docker
COPY --from=builder /evolution/runWithProvider.js ./runWithProvider.js

# Criar usuário não-root para segurança
RUN addgroup -g 1001 -S nodejs && \
    adduser -S evolution -u 1001 && \
    chown -R evolution:nodejs /evolution

USER evolution

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/manager || exit 1

ENTRYPOINT ["/bin/bash", "-c", ". ./Docker/scripts/deploy_database.sh && npm run start:prod"]