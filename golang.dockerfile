# Builder stage
FROM golang:1.23 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o golang-demo .

# Final stage
FROM alpine:latest
WORKDIR /app
COPY --from=builder /app/golang-demo .
CMD ["./golang-demo"]

# docker build -t golang-demo:latest -f golang.dockerfile .
# docker run -it --entrypoint sh golang-demo
