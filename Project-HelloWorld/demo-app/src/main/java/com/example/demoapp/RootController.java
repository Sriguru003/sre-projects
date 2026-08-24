package com.example.demoapp;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@RestController
public class RootController {

    // Keeps "/" from returning a 404 page, which some AWS health
    // checks will treat as an unhealthy target.
    @GetMapping("/")
    public Map<String, Object> root() {
        return Map.of(
                "status", "UP",
                "service", "demo-app",
                "try", new String[]{"Hello Guru Welcome to the world of SRE4"}
        );
    }
}
