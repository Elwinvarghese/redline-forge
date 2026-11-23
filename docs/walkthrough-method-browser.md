# ForgeTrack Walkthrough - Method 1: Browser-Only Guide

> Use this guide only with the local ForgeTrack training lab at `http://localhost:8080`.

## Who this is for

This method is for beginners. You need only a web browser and the ForgeTrack lab. The goal is to understand what changes when you enter normal text and then carefully test input handling.

## Step 1: Explore the application

Open the dashboard, then visit these pages:

1. **Cars** - see the racing fleet.
2. **Builds** - see normal released build records.
3. **Telemetry** - see session codes such as `EMB-Q1-07`.
4. **Race Centre** - see event information.

This is important because you need to understand the normal application before you test it.

## Step 2: Complete the search challenge

1. Open **Builds**.
2. Select **Search build registry**.
3. Search for `Apex`.
4. Notice the normal table layout: it has six pieces of information in each row.
5. In the address bar, replace the search text with the instructor-provided search payload from the main walkthrough.
6. Reload the page.

If the request works, a new row appears in the build table. The flag is shown where a build name normally appears.

### What this means

The search box was expected to search for a build name. Instead, the input changed the database request. This is the visible SQL injection exercise.

## Step 3: Complete the restricted-build challenge

1. Return to **Builds**.
2. Open any normal build record.
3. Look at the browser address. It ends in something like `id=1`.
4. The normal record shows six values: record ID, build code, build name, status, car, and notes.
5. Replace the `id` value with the instructor-provided UNION payload from the main walkthrough.
6. Reload the page.

If successful, the normal engineering-file page displays an injected record. The flag is visible in the build-name area.

### What this means

The page expects six values in its record layout. A carefully matched UNION result can be displayed as if it were a normal build record.

## Step 4: Complete the telemetry challenge

1. Open **Telemetry**.
2. Copy one real session code, such as `EMB-Q1-07`.
3. Check it in the session-availability form. You should see **Archive record located**.
4. Enter a fake code such as `nothing-here`. You should see **No archive record**.

This is your clue: the page gives two different results.

5. Use the blind-SQLi prefix test from the main walkthrough in the `session` field.
6. If the page says **Archive record located**, your letter guess is correct.
7. If it says **No archive record**, your letter guess is wrong.
8. Build the flag one character at a time until it ends with `}`.

### What this means

The website does not show the flag directly. However, its yes/no response reveals whether each guess is correct. This is called blind SQL injection.

## Step 5: Verify the fix

1. Open `/secure/builds/search?query=` in the address bar.
2. Paste the same search text that worked in Step 2.
3. This time, it should not create a new result row.

### What this means

The secure page treats your input as plain text instead of part of a database command. That is the effect of parameterized queries.

## Simple report template

For each challenge, record:

- The page and input box you used.
- What a normal request did.
- What changed after the test input.
- The flag you recovered.
- Why parameterized queries would stop the issue.
