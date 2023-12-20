import React from 'react'
import styled from 'styled-components'
import { Message, Icon } from 'semantic-ui-react'

const StyledMessage = styled(Message)`
  width: auto !important;
`

const BannerMessage = () => (
  <StyledMessage compact icon>
    <Icon name="info" />
    <Message.Content>
      <Message.Header>Seqr Updated!</Message.Header>
      <p>
        <a
          href="http://bioinfomethods.pages.mcri.edu.au/archie-documentation/seqr-release-2023-12/"
          target="_blank"
          rel="noreferrer"
        >
          Click here
        </a>
        &nbsp;to see what&apos;s new.
      </p>
    </Message.Content>
  </StyledMessage>
)

export default BannerMessage
