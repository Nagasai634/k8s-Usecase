FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# copy the fat jar (built by gradle) into the image
COPY build/libs/simple-java-gradle-docker-1.0.0.jar /app/app.jar

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
