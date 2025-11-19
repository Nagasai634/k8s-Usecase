package com.example.demo;

import org.springframework.stereotype.Controller;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class HealthController {
    
    @GetMapping("/health")
    public String health() {
        return "OK";
    }
    
    @GetMapping("/")
    public String home() {
        return "<!DOCTYPE html><html><head><title>Java App</title><style>body{font-family:Arial,sans-serif;text-align:center;padding:50px}</style></head><body><h1>Welcome to Java Application</h1><p>Application is running successfully!</p></body></html>";
    }
}
