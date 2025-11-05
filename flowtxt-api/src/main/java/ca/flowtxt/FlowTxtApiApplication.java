package ca.flowtxt;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "ca.flowtxt")
public class FlowTxtApiApplication {
    public static void main(String[] args) {
        SpringApplication.run(FlowTxtApiApplication.class, args);
    }
}