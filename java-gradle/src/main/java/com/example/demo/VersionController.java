// src/main/java/com/example/demo/VersionController.java
package com.example.demo;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class VersionController {

    @GetMapping("/")
    public String showVersion() {
        return "version"; // This will serve version.html from templates
    }

    @GetMapping("/version")
    public String getVersionInfo() {
        return "{\"version\": \"2.0\", \"color\": \"green\", \"features\": [\"Analytics\", \"Notifications\"]}";
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }
}