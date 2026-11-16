FROM dart:stable AS build
WORKDIR /workspace

# Pin the CLI to the same Serverpod release as the server runtime.
RUN dart pub global activate serverpod_cli 4.1.0
ENV PATH="/root/.pub-cache/bin:${PATH}"

# The Serverpod generator writes into the sibling client package, so the
# Docker build context is the project root rather than serverpod_server/.
COPY serverpod_server/pubspec.yaml serverpod_server/pubspec.yaml
COPY serverpod_server/config serverpod_server/config
COPY serverpod_client/pubspec.yaml serverpod_client/pubspec.yaml
RUN cd serverpod_server && dart pub get
COPY serverpod_server serverpod_server
COPY serverpod_client serverpod_client
WORKDIR /workspace/serverpod_server
RUN serverpod generate
RUN dart pub get
RUN dart compile exe bin/main.dart -o bin/server

FROM dart:stable AS runtime
WORKDIR /app
RUN useradd --create-home --uid 10001 app
COPY --from=build /workspace/serverpod_server/bin/server /app/bin/server
COPY --from=build /workspace/serverpod_server/config /app/config
COPY --from=build /workspace/serverpod_server/migrations /app/migrations
RUN chown -R app:app /app
USER app
EXPOSE 8080 8081 8082
ENTRYPOINT ["/app/bin/server", "--mode", "production", "--apply-migrations"]
