import { StyleSheet, Text, View } from 'react-native';

/** Scaffold only. Farm Manager screens, offline outbox and activation states arrive in M7. */
export default function App() {
  return (
    <View style={styles.container}>
      <Text accessibilityRole="header" style={styles.title}>
        Winfield
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  title: { fontSize: 24 },
});
