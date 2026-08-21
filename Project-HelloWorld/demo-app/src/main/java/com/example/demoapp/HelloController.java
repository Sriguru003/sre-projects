package com.example.demoapp;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.InetAddress;
import java.net.UnknownHostException;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;

@RestController
@RequestMapping("/api")
public class HelloController {

    // Set via the APP_ENV environment variable in Docker / AWS.
    // Handy for proving your container config actually reached the app.
    @Value("${app.env:local}")
    private String appEnv;

    @GetMapping("/hello")
    public Map<String, Object> hello(@RequestParam(defaultValue = "World") String name) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("message", "Hello, " + name + "!");
        body.put("environment", appEnv);
        body.put("host", hostname());
        body.put("timestamp", Instant.now().toString());
        return body;
    }

    @GetMapping("/greet/{name}")
    public Map<String, String> greet(@PathVariable String name) {
        return Map.of("greeting", "Namaste, " + name);
    }

    @GetMapping("/info")
    public Map<String, String> info() {
        return Map.of(
                "app", "demo-app",
                "java", System.getProperty("java.version"),
                "os", System.getProperty("os.name"),
                "host", hostname()
        );
    }

    private String hostname() {
        try {
            // Inside a container this is the container ID - useful for
            // seeing load balancing across tasks.
            return InetAddress.getLocalHost().getHostName();
        } catch (UnknownHostException e) {
            return "unknown";
        }
    }
}
