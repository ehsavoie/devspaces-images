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

import userEvent from '@testing-library/user-event';
import React from 'react';

import { ContainerImageField } from '@/components/ImportFromGit/RepoOptionsAccordion/AdvancedOptions/ContainerImageField';
import getComponentRenderer, { screen } from '@/services/__mocks__/getComponentRenderer';

const { createSnapshot, renderComponent } = getComponentRenderer(getComponent);

const mockOnChange = jest.fn();

describe('ContainerImageField', () => {
  afterEach(() => {
    jest.clearAllMocks();
  });

  test('snapshot', () => {
    const snapshot = createSnapshot();
    expect(snapshot.toJSON()).toMatchSnapshot();
  });

  test('container image preset value', () => {
    renderComponent('preset-container-image');

    const input = screen.getByRole('textbox');

    expect(input).toHaveValue('preset-container-image');
  });

  test('container image change', () => {
    renderComponent();

    const input = screen.getByRole('textbox');

    const containerImage = 'new-container-image';
    userEvent.paste(input, containerImage);

    expect(mockOnChange).toHaveBeenNthCalledWith(1, containerImage);

    userEvent.clear(input);
    expect(mockOnChange).toHaveBeenNthCalledWith(2, undefined);
  });
});

function getComponent(containerImage?: string) {
  return <ContainerImageField containerImage={containerImage} onChange={mockOnChange} />;
}
