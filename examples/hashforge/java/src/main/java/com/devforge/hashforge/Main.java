package com.devforge.hashforge;

import java.awt.*;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import javax.swing.*;

public class Main {
    private static final String VERSION = "1.0.0";

    public static class HashResult {
        public final String target;
        public final String sha256;
        public final String md5;

        public HashResult(String target, String sha256, String md5) {
            this.target = target;
            this.sha256 = sha256;
            this.md5 = md5;
        }

        public String toJson() {
            return String.format("{\"target\":\"%s\",\"sha256\":\"%s\",\"md5\":\"%s\"}",
                    target.replace("\"", "\\\""), sha256, md5);
        }
    }

    public static String bytesToHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }

    public static HashResult hashString(String text) throws Exception {
        byte[] inputBytes = text.getBytes(StandardCharsets.UTF_8);

        MessageDigest sha256Digest = MessageDigest.getInstance("SHA-256");
        String sha256 = bytesToHex(sha256Digest.digest(inputBytes));

        MessageDigest md5Digest = MessageDigest.getInstance("MD5");
        String md5 = bytesToHex(md5Digest.digest(inputBytes));

        return new HashResult(text, sha256, md5);
    }

    public static HashResult hashFile(String filePath) throws Exception {
        MessageDigest sha256Digest = MessageDigest.getInstance("SHA-256");
        MessageDigest md5Digest = MessageDigest.getInstance("MD5");

        try (InputStream is = new FileInputStream(filePath)) {
            byte[] buffer = new byte[8192];
            int read;
            while ((read = is.read(buffer)) != -1) {
                sha256Digest.update(buffer, 0, read);
                md5Digest.update(buffer, 0, read);
            }
        }

        String sha256 = bytesToHex(sha256Digest.digest());
        String md5 = bytesToHex(md5Digest.digest());

        return new HashResult(filePath, sha256, md5);
    }

    private static void launchGui() {
        if (GraphicsEnvironment.isHeadless()) {
            System.err.println("Entorno sin soporte gráfico (headless). Usa los argumentos de línea de comandos.");
            return;
        }

        SwingUtilities.invokeLater(() -> {
            JFrame frame = new JFrame("HashForge (Java Swing)");
            frame.setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
            frame.setSize(580, 360);
            frame.setLocationRelativeTo(null);

            JPanel panel = new JPanel(new GridBagLayout());
            panel.setBorder(BorderFactory.createEmptyBorder(15, 15, 15, 15));
            GridBagConstraints gbc = new GridBagConstraints();
            gbc.fill = GridBagConstraints.HORIZONTAL;
            gbc.insets = new Insets(5, 5, 5, 5);

            JLabel labelInput = new JLabel("Texto a calcular:");
            JTextField textInput = new JTextField("dev-forge test", 30);
            JButton btnCalc = new JButton("Calcular Hash");

            JLabel labelSha = new JLabel("SHA-256:");
            JTextField textSha = new JTextField(40);
            textSha.setEditable(false);

            JLabel labelMd5 = new JLabel("MD5:");
            JTextField textMd5 = new JTextField(40);
            textMd5.setEditable(false);

            btnCalc.addActionListener(e -> {
                try {
                    HashResult res = hashString(textInput.getText());
                    textSha.setText(res.sha256);
                    textMd5.setText(res.md5);
                } catch (Exception ex) {
                    JOptionPane.showMessageDialog(frame, "Error: " + ex.getMessage(), "Error", JOptionPane.ERROR_MESSAGE);
                }
            });

            // Grid positioning
            gbc.gridx = 0; gbc.gridy = 0; panel.add(labelInput, gbc);
            gbc.gridx = 1; gbc.gridy = 0; panel.add(textInput, gbc);
            gbc.gridx = 1; gbc.gridy = 1; panel.add(btnCalc, gbc);
            gbc.gridx = 0; gbc.gridy = 2; panel.add(labelSha, gbc);
            gbc.gridx = 1; gbc.gridy = 2; panel.add(textSha, gbc);
            gbc.gridx = 0; gbc.gridy = 3; panel.add(labelMd5, gbc);
            gbc.gridx = 1; gbc.gridy = 3; panel.add(textMd5, gbc);

            frame.getContentPane().add(panel);
            frame.setVisible(true);

            // Run initial calculation
            btnCalc.doClick();
        });
    }

    private static void printHelp() {
        System.out.println("HashForge " + VERSION + " (Java)");
        System.out.println("Uso:");
        System.out.println("  java -jar hashforge-java.jar -s <texto>    Calcula hash de una cadena");
        System.out.println("  java -jar hashforge-java.jar -f <archivo>  Calcula hash de un archivo");
        System.out.println("  java -jar hashforge-java.jar -j            Formato JSON");
        System.out.println("  java -jar hashforge-java.jar --gui         Inicia la interfaz Swing");
        System.out.println("  java -jar hashforge-java.jar -h            Muestra esta ayuda");
    }

    public static void main(String[] args) {
        if (args.length == 0) {
            if (!GraphicsEnvironment.isHeadless()) {
                launchGui();
                return;
            }
            printHelp();
            return;
        }

        String inputString = null;
        String inputFile = null;
        boolean jsonOutput = false;
        boolean forceGui = false;

        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "-s":
                case "--string":
                    if (i + 1 < args.length) inputString = args[++i];
                    break;
                case "-f":
                case "--file":
                    if (i + 1 < args.length) inputFile = args[++i];
                    break;
                case "-j":
                case "--json":
                    jsonOutput = true;
                    break;
                case "-g":
                case "--gui":
                    forceGui = true;
                    break;
                case "-h":
                case "--help":
                    printHelp();
                    return;
                default:
                    System.err.println("Opción desconocida: " + args[i]);
                    printHelp();
                    System.exit(1);
            }
        }

        if (forceGui) {
            launchGui();
            return;
        }

        try {
            HashResult result = null;
            if (inputString != null) {
                result = hashString(inputString);
            } else if (inputFile != null) {
                result = hashFile(inputFile);
            } else {
                printHelp();
                return;
            }

            if (jsonOutput) {
                System.out.println(result.toJson());
            } else {
                System.out.println("Objetivo: " + result.target);
                System.out.println("SHA-256:  " + result.sha256);
                System.out.println("MD5:      " + result.md5);
            }
        } catch (Exception e) {
            System.err.println("Error: " + e.getMessage());
            System.exit(1);
        }
    }
}

