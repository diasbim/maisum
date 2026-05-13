package com.loyaltyos.platform.config.repo;

import com.loyaltyos.platform.config.domain.ConfigSegment;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ConfigSegmentRepository extends JpaRepository<ConfigSegment, UUID> {}
