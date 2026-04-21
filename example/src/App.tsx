import { useState } from 'react';
import {
  StyleSheet,
  View,
  Text,
  TouchableOpacity,
  SafeAreaView,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { download, shareFile, openFile } from 'rn-downloader';

export default function App() {
  const [progress, setProgress] = useState<number>(0);
  const [downloading, setDownloading] = useState(false);
  const [result, setResult] = useState<string>('');
  const [downloadedFilePath, setDownloadedFilePath] = useState<string>('');

  const startDownload = async () => {
    setDownloading(true);
    setProgress(0);
    setResult('');
    setDownloadedFilePath('');

    // Sample 5MB PDF file for testing
    const SAMPLE_URL =
      'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf';

    const res = await download({
      url: SAMPLE_URL,
      onProgress: (p) => setProgress(p),
    });

    setDownloading(false);

    if (res.success) {
      setResult(`Success! Saved at: ${res.filePath}`);
      setDownloadedFilePath(res.filePath || '');
    } else {
      setResult(`Error: ${res.error}`);
    }
  };

  const handleShareFile = async () => {
    if (!downloadedFilePath) {
      Alert.alert('No File', 'Please download a file first');
      return;
    }

    const res = await shareFile({
      filePath: downloadedFilePath,
      title: 'Share PDF Document',
      subject: 'Check out this PDF',
    });

    if (res.success) {
      Alert.alert('Success', 'Share dialog opened');
    } else {
      Alert.alert('Error', res.error || 'Failed to share file');
    }
  };

  const handleOpenFile = async () => {
    if (!downloadedFilePath) {
      Alert.alert('No File', 'Please download a file first');
      return;
    }

    const res = await openFile({
      filePath: downloadedFilePath,
      mimeType: 'application/pdf',
    });

    if (res.success) {
      Alert.alert('Success', 'File opened');
    } else {
      Alert.alert('Error', res.error || 'Failed to open file');
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.card}>
        <Text style={styles.title}>🚀 rn-downloader</Text>
        <Text style={styles.subtitle}>
          Test pure native downloads instantly.
        </Text>

        <View style={styles.progressContainer}>
          <Text style={styles.progressText}>{progress}%</Text>
          <View style={styles.progressBarBg}>
            <View style={[styles.progressBarFill, { width: `${progress}%` }]} />
          </View>
        </View>

        <TouchableOpacity
          style={[styles.button, downloading && styles.buttonDisabled]}
          onPress={startDownload}
          disabled={downloading}
        >
          {downloading ? (
            <ActivityIndicator color="#FFF" />
          ) : (
            <Text style={styles.buttonText}>Download Sample PDF</Text>
          )}
        </TouchableOpacity>

        {downloadedFilePath ? (
          <View style={styles.actionButtons}>
            <TouchableOpacity
              style={[styles.button, styles.shareButton]}
              onPress={handleShareFile}
            >
              <Text style={styles.buttonText}>📤 Share File</Text>
            </TouchableOpacity>

            <TouchableOpacity
              style={[styles.button, styles.openButton]}
              onPress={handleOpenFile}
            >
              <Text style={styles.buttonText}>📂 Open File</Text>
            </TouchableOpacity>
          </View>
        ) : null}

        {result !== '' && <Text style={styles.resultText}>{result}</Text>}
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0F172A',
    justifyContent: 'center',
    alignItems: 'center',
  },
  card: {
    backgroundColor: '#1E293B',
    padding: 24,
    borderRadius: 20,
    width: '90%',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 10,
  },
  title: {
    fontSize: 22,
    fontWeight: '800',
    color: '#F8FAFC',
    marginBottom: 8,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 14,
    color: '#94A3B8',
    marginBottom: 32,
    textAlign: 'center',
  },
  progressContainer: {
    alignItems: 'center',
    marginBottom: 32,
  },
  progressText: {
    fontSize: 48,
    fontWeight: '900',
    color: '#38BDF8',
    marginBottom: 12,
  },
  progressBarBg: {
    width: '100%',
    height: 12,
    backgroundColor: '#334155',
    borderRadius: 6,
    overflow: 'hidden',
  },
  progressBarFill: {
    height: '100%',
    backgroundColor: '#38BDF8',
  },
  button: {
    backgroundColor: '#38BDF8',
    paddingVertical: 16,
    borderRadius: 12,
    alignItems: 'center',
  },
  buttonDisabled: {
    backgroundColor: '#0EA5E9',
    opacity: 0.7,
  },
  buttonText: {
    color: '#0F172A',
    fontSize: 16,
    fontWeight: '700',
  },
  resultText: {
    marginTop: 24,
    color: '#10B981',
    textAlign: 'center',
    fontSize: 12,
    fontWeight: '500',
  },
  actionButtons: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 16,
  },
  shareButton: {
    backgroundColor: '#8B5CF6',
    flex: 1,
  },
  openButton: {
    backgroundColor: '#F59E0B',
    flex: 1,
  },
});
