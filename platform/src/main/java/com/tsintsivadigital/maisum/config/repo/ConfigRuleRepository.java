package com.tsintsivadigital.maisum.config.repo;

import com.tsintsivadigital.maisum.config.domain.ConfigRule;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConfigRuleRepository extends JpaRepository<ConfigRule, UUID> {
  List<ConfigRule> findByConfigKeyOrderByPriorityAsc(String configKey);
}
