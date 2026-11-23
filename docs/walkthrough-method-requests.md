# ForgeTrack Walkthrough - Method 2: Request-by-Request Guide

> Use this guide only with the local ForgeTrack training lab at `http://localhost:8080`.

## Who this is for

This method is for learners who prefer to see HTTP requests clearly. You can use Burp Suite Repeater, a browser developer tool, or curl. The payload details remain in the main instructor walkthrough; this guide explains the process in plain language.

## Step 1: Send normal requests first

Start by sending normal requests. These provide a baseline.

```http
GET /builds/search?query=Apex HTTP/1.1
Host: localhost:8080
```

Expected result: a normal build-search result.

```http
GET /builds/view?id=1 HTTP/1.1
Host: localhost:8080
```

Expected result: one normal build record.

```http
GET /telemetry/check?session=EMB-Q1-07 HTTP/1.1
Host: localhost:8080
```

Expected result: HTTP `200`.

Then try a missing session:

```http
GET /telemetry/check?session=not-real HTTP/1.1
Host: localhost:8080
```

Expected result: HTTP `404`.

Write these results down. They are your comparison points.

## Step 2: Search request method

1. Send the normal build search request to Repeater.
2. Change only the value after `query=`.
3. Insert the search payload from the main walkthrough.
4. Send the request again.
5. Compare the body of the response with the normal response.

### What to look for

- A new row that is not a real build.
- A flag where the build name is normally printed.
- The response is still a normal-looking HTML page, not an error message.

This shows why checking page content is useful even when the application hides database errors.

## Step 3: Build-record request method

1. Send `/builds/view?id=1` to Repeater.
2. Replace only the value after `id=`.
3. Use the six-column UNION payload from the main walkthrough.
4. Send the request.

### What to look for

The response should still use the normal engineering-file page. Compare its fields with a normal record:

| Normal page field | Meaning during the test |
| --- | --- |
| Build code | The selected table label. |
| Build name | Where the returned flag appears. |
| Status | A simple label such as `flag`. |
| Car | A harmless placeholder such as `lab`. |
| Notes | A harmless placeholder such as `retrieved`. |

This demonstrates why the number and order of selected columns matter.

## Step 4: Blind-request method

1. Send the known-good telemetry request to Repeater.
2. Keep the request path unchanged.
3. Change only the `session` value to the prefix-test value from the main walkthrough.
4. Send the request.
5. Check the HTTP status code first.

| Status | Meaning |
| --- | --- |
| `200` | Your current prefix guess is correct. |
| `404` | Your current prefix guess is wrong. |

Repeat using one extra character each time. A request tool is helpful because it makes it easy to compare status codes and save each request in history.

## Step 5: Test the secure endpoint

Copy the request that succeeded against the vulnerable build-search page. Change only the route:

```http
GET /secure/builds/search?query=YOUR_URL_ENCODED_TEST_VALUE HTTP/1.1
Host: localhost:8080
```

Expected result: the request returns a normal page but does not create an injected row. The input remains a search string.

## How to explain your result

Use this plain-language conclusion:

> The vulnerable route built a database command by joining user input into SQL text. The secure route sent the user input separately as a parameter, so it was treated as text and could not change the command structure.

## Checklist

- [ ] Recorded normal response behavior.
- [ ] Compared vulnerable and secure search responses.
- [ ] Used a six-column UNION result for the record route.
- [ ] Verified the blind `200`/`404` response difference.
- [ ] Kept all testing inside the local ForgeTrack lab.
