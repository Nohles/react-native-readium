import React from 'react';
import { Image, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import type { ImageSourcePropType } from 'react-native';
import MaterialIcons from 'react-native-vector-icons/MaterialIcons';
import type { AudiobookPlaybackState } from 'react-native-readium';

interface AudiobookMiniPlayerProps {
  playbackState: AudiobookPlaybackState | null;
  title?: string;
  subtitle?: string;
  artworkSource?: ImageSourcePropType;
  onPress?: () => void;
  onPlay: () => void;
  onPause: () => void;
  onNext: () => void;
}

/**
 * @deprecated Prefer building app-specific audiobook UI with
 * `useAudiobookPlayer` from `react-native-readium`.
 */
export const AudiobookMiniPlayer: React.FC<AudiobookMiniPlayerProps> = ({
  playbackState,
  title = 'Audiobook',
  subtitle,
  artworkSource,
  onPress,
  onPlay,
  onPause,
  onNext,
}) => {
  if (!playbackState) {
    return null;
  }

  const displayTitle = title;
  const displaySubtitle = playbackState.currentTitle || subtitle || title;
  const handlePlayPause = playbackState.isPlaying ? onPause : onPlay;

  const content = (
    <View style={styles.container}>
      <View style={styles.artwork}>
        {artworkSource ? (
          <Image source={artworkSource} style={styles.artworkImage} />
        ) : (
          <MaterialIcons name="headset" size={28} color="#E7E7E7" />
        )}
      </View>

      <View style={styles.textContainer}>
        <Text style={styles.title} numberOfLines={1}>
          {displayTitle}
        </Text>
        <Text style={styles.subtitle} numberOfLines={1}>
          {displaySubtitle}
        </Text>
      </View>

      <TouchableOpacity
        style={styles.controlButton}
        onPress={handlePlayPause}
        accessibilityRole="button"
        accessibilityLabel={
          playbackState.isPlaying ? 'Pause audiobook' : 'Play audiobook'
        }
      >
        <MaterialIcons
          name={playbackState.isPlaying ? 'pause' : 'play-arrow'}
          size={38}
          color="#FFF"
        />
      </TouchableOpacity>

      <TouchableOpacity
        style={styles.controlButton}
        onPress={onNext}
        accessibilityRole="button"
        accessibilityLabel="Next audiobook section"
      >
        <MaterialIcons name="skip-next" size={38} color="#FFF" />
      </TouchableOpacity>
    </View>
  );

  if (!onPress) {
    return content;
  }

  return (
    <TouchableOpacity
      activeOpacity={0.9}
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel="Open audiobook player"
    >
      {content}
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
  container: {
    minHeight: 72,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#626262',
    borderTopWidth: StyleSheet.hairlineWidth,
    borderTopColor: '#505050',
  },
  artwork: {
    width: 72,
    height: 72,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#1F1F1F',
  },
  artworkImage: {
    width: '100%',
    height: '100%',
    resizeMode: 'cover',
  },
  textContainer: {
    flex: 1,
    minWidth: 0,
    paddingHorizontal: 16,
  },
  title: {
    color: '#E6E6E6',
    fontSize: 21,
    fontWeight: '400',
  },
  subtitle: {
    marginTop: 2,
    color: '#FFF',
    fontSize: 21,
    fontWeight: '700',
  },
  controlButton: {
    width: 64,
    height: 72,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
