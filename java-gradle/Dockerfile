# FROM eclipse-temurin:17-jre-alpine

# WORKDIR /app

# # copy the fat jar (built by gradle) into the image
# COPY build/libs/simple-java-gradle-docker-1.0.0.jar /app/app.jar

# EXPOSE 8080

# ENTRYPOINT ["java", "-jar", "/app/app.jar"]


FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Copy the built jar file
COPY build/libs/*.jar app.jar

# Create a non-root user
RUN adduser -D -u 1000 javauser
USER javauser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/actuator/health || exit 1

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]