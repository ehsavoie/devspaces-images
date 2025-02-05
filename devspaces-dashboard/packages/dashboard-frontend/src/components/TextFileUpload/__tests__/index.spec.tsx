/*
 * Copyright (c) 2018-2024 Red Hat, Inc.
 * This program and the accompanying materials are made
 * available under the terms of the Eclipse Public License 2.0
 * which is available at https://www.eclipse.org/legal/epl-2.0/
 *
 * SPDX-License-Identifier: EPL-2.0
 *
 * Contributors:
 *   Red Hat, Inc. - initial API and implementation
 */

import { ValidatedOptions } from '@patternfly/react-core';
import userEvent from '@testing-library/user-event';
import React from 'react';

import { TextFileUpload } from '@/components/TextFileUpload';
import getComponentRenderer, { screen, waitFor } from '@/services/__mocks__/getComponentRenderer';

const { renderComponent, createSnapshot } = getComponentRenderer(getComponent);

const fieldId = 'text-file-upload-id';
const fileNamePlaceholder = 'Drag end drop file here';
const textAreaPlaceholder = 'Paste your content here';
const mockOnChange = jest.fn();

describe('TextFileUpload', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  test('snapshot, validation is in the default state', () => {
    const snapshot = createSnapshot(ValidatedOptions.default);
    expect(snapshot.toJSON()).toMatchSnapshot();
  });

  test('snapshot, validation is in the error state', () => {
    const snapshot = createSnapshot(ValidatedOptions.error);
    expect(snapshot.toJSON()).toMatchSnapshot();
  });

  test('File uploader controls', () => {
    renderComponent(ValidatedOptions.default);

    const fileUploader = screen.queryByTestId(fieldId);

    // file uploader is rendered
    expect(fileUploader).not.toBeNull();

    // file input field
    const fileInput = screen.queryByPlaceholderText(fileNamePlaceholder);
    expect(fileInput).not.toBeNull();
    expect(fileInput).toHaveAttribute('readonly');

    // Upload button
    const uploadButton = screen.queryByText('Upload');
    expect(uploadButton).not.toBeNull();
    expect(uploadButton).toBeEnabled();

    // Clear button
    const clearButton = screen.queryByText('Clear');
    expect(clearButton).not.toBeNull();
    expect(clearButton).toBeDisabled();

    // content input field
    const contentInput = screen.queryByPlaceholderText(textAreaPlaceholder);
    expect(contentInput).not.toBeNull();
    expect(contentInput).not.toHaveAttribute('readonly');
    expect(contentInput).toBeEnabled();
  });

  describe('Upload file', () => {
    test('should handle a valid file', async () => {
      renderComponent(ValidatedOptions.default);

      const contentInput = screen.getByPlaceholderText(textAreaPlaceholder);

      const fileInput = screen.getByPlaceholderText(fileNamePlaceholder);

      const clearButton = screen.getByText('Clear');

      /* Upload a file */

      const fileContent = 'file-content';
      const file = new File([fileContent], 'file.txt', { type: 'text/plain' });

      const fileUploader = screen.getByTestId(fieldId);
      const fileUploadInput = fileUploader.querySelector('input[type="file"]');
      userEvent.upload(fileUploadInput!, file);

      await waitFor(() => expect(mockOnChange).toHaveBeenCalledWith(fileContent, true));

      expect(fileInput).toHaveValue(file.name);
      expect(clearButton).toBeEnabled();
      expect(contentInput).not.toBeInTheDocument();
      expect(screen.queryByTestId('text-file-upload-preview')).toBeInTheDocument();

      /* Clear the field */

      userEvent.click(clearButton);

      expect(fileInput).toHaveValue('');
      expect(clearButton).toBeDisabled();
    });
  });

  describe('Paste content', () => {
    test('should handle a valid content', async () => {
      renderComponent(ValidatedOptions.default);

      const contentInput = screen.getByPlaceholderText(textAreaPlaceholder);

      const clearButton = screen.getByText('Clear');

      const fileInput = screen.getByPlaceholderText(fileNamePlaceholder);

      /* Paste a content */

      const content = 'content';
      userEvent.paste(contentInput, content);

      await waitFor(() => expect(mockOnChange).toHaveBeenCalledWith(content, false));

      expect(fileInput).toHaveValue('');
      expect(clearButton).toBeEnabled();
      expect(contentInput).toHaveTextContent(content);
      expect(contentInput).not.toHaveAttribute('readonly');
      expect(screen.queryByTestId('text-file-upload-preview')).not.toBeInTheDocument();

      /* Clear the field */

      userEvent.click(clearButton);

      expect(contentInput).toHaveValue('');
      expect(clearButton).toBeDisabled();
    });
  });
});

function getComponent(validated: ValidatedOptions): React.ReactElement {
  return (
    <TextFileUpload
      fieldId={fieldId}
      fileNamePlaceholder={fileNamePlaceholder}
      textAreaPlaceholder={textAreaPlaceholder}
      validated={validated}
      onChange={mockOnChange}
    />
  );
}
