import { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Alert,
  Image,
  TextInput,
} from 'react-native';
import { urlToBase64 } from '../../src';

export default function UrlToBase64Example() {
  const [url, setUrl] = useState('https://picsum.photos/400/300');
  const [dataUri, setDataUri] = useState<string>('');
  const [mimeType, setMimeType] = useState<string>('');
  const [loading, setLoading] = useState(false);

  const handleConvert = async () => {
    if (!url.trim()) {
      Alert.alert('Error', 'Please enter a URL');
      return;
    }

    setLoading(true);
    try {
      const result = await urlToBase64({ url: url.trim() });

      if (result.success && result.dataUri) {
        setDataUri(result.dataUri);
        setMimeType(result.mimeType || 'unknown');
        Alert.alert(
          'Success',
          `Converted to base64!\nMIME Type: ${result.mimeType}`
        );
      } else {
        Alert.alert('Error', result.error || 'Failed to convert');
      }
    } catch (error: any) {
      Alert.alert('Error', error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleClear = () => {
    setDataUri('');
    setMimeType('');
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>URL to Base64 Converter</Text>

      <TextInput
        style={styles.input}
        value={url}
        onChangeText={setUrl}
        placeholder="Enter image/video/gif URL"
        autoCapitalize="none"
        autoCorrect={false}
      />

      <View style={styles.buttonRow}>
        <TouchableOpacity
          style={[styles.button, loading && styles.buttonDisabled]}
          onPress={handleConvert}
          disabled={loading}
        >
          <Text style={styles.buttonText}>
            {loading ? 'Converting...' : 'Convert to Base64'}
          </Text>
        </TouchableOpacity>

        {dataUri ? (
          <TouchableOpacity
            style={[styles.button, styles.clearButton]}
            onPress={handleClear}
          >
            <Text style={styles.buttonText}>Clear</Text>
          </TouchableOpacity>
        ) : null}
      </View>

      {dataUri ? (
        <View style={styles.resultContainer}>
          <Text style={styles.resultLabel}>Result:</Text>
          <Text style={styles.mimeType}>MIME Type: {mimeType}</Text>

          {mimeType.startsWith('image/') ? (
            <View style={styles.imageContainer}>
              <Image
                source={{ uri: dataUri }}
                style={styles.image}
                resizeMode="contain"
              />
              <Text style={styles.imageCaption}>
                Image loaded from base64 data URI
              </Text>
            </View>
          ) : null}

          <View style={styles.base64Container}>
            <Text style={styles.base64Label}>Base64 String (truncated):</Text>
            <Text style={styles.base64Text} numberOfLines={3}>
              {dataUri.substring(0, 200)}...
            </Text>
          </View>
        </View>
      ) : null}

      <View style={styles.infoContainer}>
        <Text style={styles.infoText}>
          This example demonstrates:{'\n\n'}• Converting image URLs to base64
          {'\n'}• Auto MIME type detection{'\n'}• Generating data URIs{'\n'}•
          Using base64 in Image components{'\n\n'}
          Try URLs for: images, videos, gifs, PDFs
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 20,
    backgroundColor: '#f5f5f5',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 20,
    textAlign: 'center',
  },
  input: {
    backgroundColor: 'white',
    padding: 12,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: '#ddd',
    marginBottom: 16,
    fontSize: 14,
  },
  buttonRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 20,
  },
  button: {
    flex: 1,
    backgroundColor: '#007AFF',
    padding: 16,
    borderRadius: 8,
  },
  clearButton: {
    backgroundColor: '#FF3B30',
  },
  buttonDisabled: {
    backgroundColor: '#ccc',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: '600',
    textAlign: 'center',
  },
  resultContainer: {
    backgroundColor: 'white',
    padding: 16,
    borderRadius: 8,
    marginBottom: 20,
  },
  resultLabel: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 12,
    color: '#2e7d32',
  },
  mimeType: {
    fontSize: 14,
    color: '#666',
    marginBottom: 16,
    fontFamily: 'monospace',
  },
  imageContainer: {
    marginBottom: 16,
    alignItems: 'center',
  },
  image: {
    width: '100%',
    height: 200,
    backgroundColor: '#f0f0f0',
    borderRadius: 8,
    marginBottom: 8,
  },
  imageCaption: {
    fontSize: 12,
    color: '#666',
    fontStyle: 'italic',
  },
  base64Container: {
    backgroundColor: '#f5f5f5',
    padding: 12,
    borderRadius: 8,
  },
  base64Label: {
    fontSize: 12,
    fontWeight: '600',
    marginBottom: 8,
    color: '#555',
  },
  base64Text: {
    fontSize: 10,
    color: '#333',
    fontFamily: 'monospace',
  },
  infoContainer: {
    padding: 16,
    backgroundColor: '#fff3e0',
    borderRadius: 8,
  },
  infoText: {
    fontSize: 14,
    color: '#e65100',
    lineHeight: 20,
  },
});
