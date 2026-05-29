import React, { useState, useCallback } from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import Slider from '@react-native-community/slider';
import type { ReadiumProps } from 'react-native-readium';
import { createComicPreferences, RANGES } from 'react-native-readium';
import { ReaderButton } from './ReaderButton';
import { BaseModal } from './BaseModal';
import { modalStyles, colors } from '../styles/modal';

interface Props {
  preferences: ReadiumProps['preferences'];
  onChange: (preferences: ReadiumProps['preferences']) => void;
}

type Theme = NonNullable<ReadiumProps['preferences']['theme']>;
type ReadingProgression = NonNullable<
  ReadiumProps['preferences']['readingProgression']
>;
type Fit = NonNullable<ReadiumProps['preferences']['fit']>;
type Spread = NonNullable<ReadiumProps['preferences']['spread']>;
type CanvasMode = 'webtoon' | 'singlePage' | 'doublePage';

const THEME_LABELS: Record<Theme, string> = {
  light: 'Light',
  dark: 'Dark',
  sepia: 'Sepia',
};

const READING_PROGRESSION_LABELS: Record<ReadingProgression, string> = {
  ltr: 'LTR',
  rtl: 'RTL',
};

const FIT_LABELS: Record<Fit, string> = {
  auto: 'Auto',
  page: 'Page',
  width: 'Width',
};

const SPREAD_LABELS: Record<Spread, string> = {
  auto: 'Auto',
  never: 'Never',
  always: 'Always',
};

const CANVAS_MODE_LABELS: Record<CanvasMode, string> = {
  webtoon: 'Webtoon',
  singlePage: 'Single',
  doublePage: 'Double',
};

const OptionRow = <T extends string>({
  value,
  options,
  labels,
  onChange,
}: {
  value: T;
  options: T[];
  labels: Record<T, string>;
  onChange: (value: T) => void;
}) => (
  <View style={styles.optionRow}>
    {options.map((option) => {
      const isActive = value === option;

      return (
        <TouchableOpacity
          key={option}
          style={[styles.optionButton, isActive && styles.optionButtonActive]}
          onPress={() => onChange(option)}
          activeOpacity={0.7}
        >
          <Text
            style={[
              styles.optionButtonText,
              isActive && styles.optionButtonTextActive,
            ]}
          >
            {labels[option]}
          </Text>
        </TouchableOpacity>
      );
    })}
  </View>
);

export const PreferencesEditor = ({ preferences, onChange }: Props) => {
  const [isOpen, setIsOpen] = useState<boolean>(false);

  const nextAppearance = useCallback((theme?: Theme) => {
    if (theme === 'light') {
      return 'dark';
    } else if (theme === 'dark') {
      return 'sepia';
    } else {
      return 'light';
    }
  }, []);

  const handleThemeChange = () => {
    onChange({
      ...preferences,
      theme: nextAppearance(preferences.theme),
    });
  };

  const handleFontSizeChange = (fontSize: number) => {
    onChange({
      ...preferences,
      fontSize,
      typeScale: fontSize,
    });
  };

  const handlePageMarginsChange = (pageMargins: number) => {
    onChange({
      ...preferences,
      pageMargins,
    });
  };

  const handleReadingProgressionChange = (
    readingProgression: ReadingProgression
  ) => {
    onChange({
      ...preferences,
      readingProgression,
    });
  };

  const handleScrollChange = (scroll: boolean) => {
    onChange({
      ...preferences,
      scroll,
    });
  };

  const handleFitChange = (fit: Fit) => {
    onChange({
      ...preferences,
      fit,
    });
  };

  const handleSpreadChange = (spread: Spread) => {
    onChange({
      ...preferences,
      spread,
    });
  };

  const handleCanvasModeChange = (canvasMode: CanvasMode) => {
    onChange(createComicPreferences({ canvasMode }, preferences));
  };

  const handleVerticalTextChange = (verticalText: boolean) => {
    onChange({
      ...preferences,
      verticalText,
      scroll: verticalText ? true : preferences.scroll,
    });
  };

  return (
    <>
      <ReaderButton size={35} name="settings" onPress={() => setIsOpen(true)} />

      <BaseModal
        visible={isOpen}
        title="Reader Settings"
        onClose={() => setIsOpen(false)}
      >
        {/* Theme Setting */}
        <View style={modalStyles.cardItem}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Theme</Text>
            <TouchableOpacity
              style={styles.themeButton}
              onPress={handleThemeChange}
              activeOpacity={0.7}
            >
              <Text style={styles.themeButtonText}>
                {THEME_LABELS[preferences.theme || 'light']}
              </Text>
            </TouchableOpacity>
          </View>
          <Text style={styles.settingDescription}>
            Change the reading theme appearance
          </Text>
        </View>

        {/* Font Size Setting */}
        <View style={modalStyles.cardItem}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Font Size</Text>
            <Text style={styles.settingValue}>
              {preferences.fontSize?.toFixed(1) || '1.0'}
            </Text>
          </View>
          <Slider
            style={styles.slider}
            minimumValue={RANGES.fontSize[0]}
            maximumValue={RANGES.fontSize[1]}
            step={0.1}
            value={preferences.fontSize}
            onSlidingComplete={handleFontSizeChange}
            minimumTrackTintColor={colors.primary}
            maximumTrackTintColor={colors.border.secondary}
            thumbTintColor={colors.primary}
          />
          <View style={styles.rangeLabels}>
            <Text style={styles.rangeLabel}>Small</Text>
            <Text style={styles.rangeLabel}>Large</Text>
          </View>
        </View>

        {/* Page Margin Setting */}
        <View style={modalStyles.cardItem}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Page Margin</Text>
            <Text style={styles.settingValue}>
              {preferences.pageMargins || 0}
            </Text>
          </View>
          <Slider
            style={styles.slider}
            minimumValue={RANGES.pageMargins[0]}
            maximumValue={RANGES.pageMargins[1]}
            step={1}
            value={preferences.pageMargins}
            onSlidingComplete={handlePageMarginsChange}
            minimumTrackTintColor={colors.primary}
            maximumTrackTintColor={colors.border.secondary}
            thumbTintColor={colors.primary}
          />
          <View style={styles.rangeLabels}>
            <Text style={styles.rangeLabel}>Narrow</Text>
            <Text style={styles.rangeLabel}>Wide</Text>
          </View>
        </View>

        <View style={modalStyles.cardItem}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Reading Direction</Text>
          </View>
          <OptionRow
            value={preferences.readingProgression || 'ltr'}
            options={['ltr', 'rtl']}
            labels={READING_PROGRESSION_LABELS}
            onChange={handleReadingProgressionChange}
          />
        </View>

        <View style={modalStyles.cardItem}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Page Mode</Text>
          </View>
          <OptionRow
            value={preferences.scroll ? 'scroll' : 'paged'}
            options={['paged', 'scroll']}
            labels={{ paged: 'Paged', scroll: 'Scroll' }}
            onChange={(mode) => handleScrollChange(mode === 'scroll')}
          />
        </View>

        <View style={modalStyles.cardItem}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Comic Canvas</Text>
          </View>
          <OptionRow
            value={comicCanvasMode(preferences)}
            options={['webtoon', 'singlePage', 'doublePage']}
            labels={CANVAS_MODE_LABELS}
            onChange={handleCanvasModeChange}
          />
        </View>

        <View style={modalStyles.cardItem}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Fit</Text>
          </View>
          <OptionRow
            value={preferences.fit || 'page'}
            options={['page', 'width', 'auto']}
            labels={FIT_LABELS}
            onChange={handleFitChange}
          />
        </View>

        <View style={modalStyles.cardItem}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Spread</Text>
          </View>
          <OptionRow
            value={preferences.spread || 'auto'}
            options={['auto', 'never', 'always']}
            labels={SPREAD_LABELS}
            onChange={handleSpreadChange}
          />
        </View>

        <View style={[modalStyles.cardItem, modalStyles.cardItemLast]}>
          <View style={styles.settingHeader}>
            <Text style={styles.settingLabel}>Vertical Mode</Text>
            <TouchableOpacity
              style={[
                styles.themeButton,
                preferences.verticalText && styles.optionButtonActive,
              ]}
              onPress={() =>
                handleVerticalTextChange(!preferences.verticalText)
              }
              activeOpacity={0.7}
            >
              <Text style={styles.themeButtonText}>
                {preferences.verticalText ? 'On' : 'Off'}
              </Text>
            </TouchableOpacity>
          </View>
          <Text style={styles.settingDescription}>
            Use vertical text flow where the native reader supports it
          </Text>
        </View>
      </BaseModal>
    </>
  );
};

function comicCanvasMode(preferences: ReadiumProps['preferences']): CanvasMode {
  if (preferences.scroll) {
    return 'webtoon';
  }

  return preferences.spread === 'always' ? 'doublePage' : 'singlePage';
}

const styles = StyleSheet.create({
  settingHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  settingLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text.primary,
  },
  settingValue: {
    fontSize: 15,
    fontWeight: '500',
    color: colors.primary,
  },
  settingDescription: {
    fontSize: 13,
    color: colors.text.secondary,
    marginTop: 4,
  },
  themeButton: {
    backgroundColor: colors.primary,
    paddingVertical: 8,
    paddingHorizontal: 16,
    borderRadius: 6,
    minWidth: 80,
    alignItems: 'center',
  },
  themeButtonText: {
    color: '#FFFFFF',
    fontSize: 14,
    fontWeight: '600',
  },
  slider: {
    width: '100%',
    height: 40,
    marginVertical: 8,
  },
  rangeLabels: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 4,
  },
  rangeLabel: {
    fontSize: 12,
    color: colors.text.tertiary,
  },
  optionRow: {
    flexDirection: 'row',
    gap: 8,
    flexWrap: 'wrap',
  },
  optionButton: {
    minWidth: 72,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: colors.border.secondary,
    backgroundColor: '#FFFFFF',
    alignItems: 'center',
  },
  optionButtonActive: {
    borderColor: colors.primary,
    backgroundColor: colors.primary,
  },
  optionButtonText: {
    color: colors.text.primary,
    fontSize: 14,
    fontWeight: '600',
  },
  optionButtonTextActive: {
    color: '#FFFFFF',
  },
});
