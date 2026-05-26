package com.tsintsivadigital.maisum.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.security.SecurityScheme;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class OpenApiConfig {
  @Bean
  public OpenAPI platformOpenApi() {
    return new OpenAPI()
        .info(
            new Info()
                .title("Maisum Platform API")
                .description("API documentation for loyalty and platform services")
                .version("v1")
                .license(new License().name("Proprietary")))
        .components(
            new io.swagger.v3.oas.models.Components()
                .addSecuritySchemes(
                    "X-Admin-Key",
                    new SecurityScheme()
                        .type(SecurityScheme.Type.APIKEY)
                        .in(SecurityScheme.In.HEADER)
                        .name("X-Admin-Key")));
  }
}
