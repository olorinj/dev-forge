package com.devforge.hashforge;

import android.app.Activity;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(32, 32, 32, 32);

        TextView title = new TextView(this);
        title.setText("HashForge Mobile (Android)");
        title.setTextSize(20);
        layout.addView(title);

        final EditText input = new EditText(this);
        input.setHint("Introduce texto a hashear");
        input.setText("dev-forge test");
        layout.addView(input);

        Button btn = new Button(this);
        btn.setText("Calcular Hashes");
        layout.addView(btn);

        final TextView resultSha = new TextView(this);
        resultSha.setTextIsSelectable(true);
        layout.addView(resultSha);

        final TextView resultMd5 = new TextView(this);
        resultMd5.setTextIsSelectable(true);
        layout.addView(resultMd5);

        btn.setOnClickListener(v -> {
            String text = input.getText().toString();
            try {
                byte[] bytes = text.getBytes(StandardCharsets.UTF_8);

                MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
                byte[] dSha = sha256.digest(bytes);
                StringBuilder sbSha = new StringBuilder();
                for (byte b : dSha) sbSha.append(String.format("%02x", b));

                MessageDigest md5 = MessageDigest.getInstance("MD5");
                byte[] dMd5 = md5.digest(bytes);
                StringBuilder sbMd5 = new StringBuilder();
                for (byte b : dMd5) sbMd5.append(String.format("%02x", b));

                resultSha.setText("SHA-256:\n" + sbSha.toString());
                resultMd5.setText("MD5:\n" + sbMd5.toString());
            } catch (Exception e) {
                resultSha.setText("Error: " + e.getMessage());
            }
        });

        btn.performClick();
        setContentView(layout);
    }
}
