package com.tsintsivadigital.maisum.streaks;

import java.time.LocalDate;

public class MerchantStreakResponse {
  private final int streakDays;
  private final LocalDate lastActiveDay;

  public MerchantStreakResponse(int streakDays, LocalDate lastActiveDay) {
    this.streakDays = streakDays;
    this.lastActiveDay = lastActiveDay;
  }

  public int getStreakDays() {
    return streakDays;
  }

  public LocalDate getLastActiveDay() {
    return lastActiveDay;
  }
}
