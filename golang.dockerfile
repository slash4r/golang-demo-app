# Builder stage with CompileDaemon
FROM golang:1.23 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

RUN go install github.com/githubnemo/CompileDaemon@latest

COPY . .

# Final stage
FROM golang:1.23 AS dev
WORKDIR /app

COPY --from=builder /go/bin/CompileDaemon /usr/local/bin/CompileDaemon
COPY --from=builder /app /app

CMD ["CompileDaemon", "--build=go build -o golang-demo .", "--command=./golang-demo", "--exclude-dir=.git", "--exclude-dir=vendor", "--exclude-dir=terraform", "--verbose"]
